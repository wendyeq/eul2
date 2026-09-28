import CoreFoundation
import Foundation
import Security

/// Read-only credentials and ephemeral refresh; no credentials escape into snapshots.
enum AntigravityQuotaClient {
    private static let clientID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    private static let clientSecret = "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"

    struct Dependencies {
        var command: (String, [String]) -> String = runCommand
        var read: (String) -> Data? = { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
        var exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
        var http: (URLRequest) -> (Int, Data)? = request
        var home = FileManager.default.homeDirectoryForCurrentUser.path
    }

    static func fetchSync(_ dependencies: Dependencies = Dependencies()) -> QuotaProviderSnapshot {
        guard let credential = credential(dependencies) else { return localQuota(dependencies) }
        var refresh = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        refresh.httpMethod = "POST"
        refresh.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "refresh_token", value: credential.refresh),
        ]
        refresh.httpBody = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        guard let (status, data) = dependencies.http(refresh) else { return .failedEmpty }
        let token = json(data)
        let tokenError = token?["error"] as? String
        // Client rejection is not an expired user session, even when Google returns 401.
        if tokenError == "invalid_client" {
            return QuotaProviderSnapshot(kind: .failed, meters: [], failureReason: .clientAuthentication)
        }
        if status == 401 || tokenError == "invalid_grant" { return .unsigned }
        guard (200..<300).contains(status), let access = token?["access_token"] as? String, !access.isEmpty else { return .failedEmpty }
        guard let assist = post("https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist", body: ["metadata": ["ideType": "ANTIGRAVITY"]], access: access, dependencies: dependencies),
              let project = projectID(assist),
              let summary = post("https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary", body: ["project": project], access: access, dependencies: dependencies)
        else { return .failedEmpty }
        return parse(summary)
    }

    static func projectID(_ root: [String: Any]) -> String? {
        for container in [root, root["response"] as? [String: Any] ?? [:]] {
            for key in ["cloudaicompanionProject", "projectId", "project"] {
                let value = container[key]
                let object = value as? [String: Any]
                for candidate in [value as? String, object?["id"] as? String, object?["projectId"] as? String] {
                    if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return candidate }
                }
            }
        }
        return nil
    }

    static func parse(_ root: [String: Any]) -> QuotaProviderSnapshot {
        let response = root["response"] as? [String: Any]
        let groups = root["groups"] as? [[String: Any]] ?? response?["groups"] as? [[String: Any]] ?? []
        var meters: [String: QuotaMeter] = [:]
        for group in groups {
            let name = ((group["displayName"] as? String) ?? (group["name"] as? String) ?? "").lowercased()
            let model = name.contains("claude") || name.contains("gpt") ? "claude_gpt" : "gemini"
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                let identifiers = ["bucketId", "id", "window"].compactMap { bucket[$0] as? String }.joined(separator: " ").lowercased()
                let weekly = identifiers.contains("weekly")
                guard weekly || ["5h", "5-hour", "session"].contains(where: identifiers.contains),
                      let remaining = bucket["remainingFraction"] as? NSNumber,
                      CFGetTypeID(remaining) != CFBooleanGetTypeID(), remaining.doubleValue.isFinite else { continue }
                let id = model + (weekly ? "_weekly" : "_5h")
                let reset = (bucket["resetTime"] as? String).flatMap(rfc3339)
                guard meters[id] == nil else { continue }
                let remainingFraction = min(1, max(0, remaining.doubleValue))
                let duration: TimeInterval = weekly ? 604_800 : 18000
                meters[id] = QuotaMeter(
                    id: id,
                    labelKey: "quota.antigravity.\(id)",
                    usedPercent: (1 - remainingFraction) * 100,
                    windowStart: reset?.addingTimeInterval(-duration),
                    resetsAt: reset
                )
            }
        }
        let ordered = ["gemini_5h", "gemini_weekly", "claude_gpt_5h", "claude_gpt_weekly"].compactMap { meters[$0] }
        return ordered.isEmpty ? .failedEmpty : QuotaProviderSnapshot(kind: .ready, meters: ordered)
    }

    static func rfc3339(_ value: String) -> Date? {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    struct Credential {
        let refresh: String
        let id: String?
    }

    static func stored(_ data: Data?) -> Credential? {
        guard let data, var text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let prefix = "go-keyring-base64:"
        if text.hasPrefix(prefix) {
            guard let decoded = Data(base64Encoded: String(text.dropFirst(prefix.count))), let string = String(data: decoded, encoding: .utf8) else { return nil }
            text = string
        }
        guard let root = json(Data(text.utf8)), let token = root["token"] as? [String: Any], let refresh = token["refresh_token"] as? String, !refresh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Credential(refresh: refresh, id: root["id_token"] as? String)
    }

    static func credential(_ dependencies: Dependencies) -> Credential? {
        let keychain = dependencies.command(
            "/usr/bin/security",
            ["find-generic-password", "-s", "gemini", "-a", "antigravity", "-w"]
        )
        if let value = stored(Data(keychain.utf8)) { return value }
        let jetski = dependencies.home + "/.gemini/jetski-standalone-oauth-token"
        if let value = stored(dependencies.read(jetski)) { return value }

        let base = dependencies.home + "/Library/Application Support/"
        let root = base + (dependencies.exists(base + "Antigravity IDE") ? "Antigravity IDE" : "Antigravity")
        let path = root + "/User/globalStorage/state.vscdb"
        guard dependencies.exists(path) else { return nil }
        let value = dependencies.command(
            "/usr/bin/sqlite3",
            ["-readonly", path, "SELECT value FROM ItemTable WHERE key = 'antigravityUnifiedStateSync.oauthToken';"]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: value) else { return nil }
        return legacy(data)
    }

    /// Length-delimited protobuf fields; skips other supported wire types with bounds checks.
    static func fields(_ data: Data) -> [(Int, Data)] {
        let bytes = Array(data)
        var offset = 0
        var result: [(Int, Data)] = []
        func varint() -> UInt64? {
            var value: UInt64 = 0
            for shift in stride(from: 0, through: 63, by: 7) {
                guard offset < bytes.count else { return nil }
                let byte = bytes[offset]
                offset += 1
                if shift == 63, byte > 1 { return nil }
                value |= UInt64(byte & 127) << shift
                if byte & 128 == 0 { return value }
            }
            return nil
        }
        while offset < bytes.count {
            guard let tag = varint(), tag >> 3 > 0 else { return [] }
            switch tag & 7 {
            case 0: guard varint() != nil else { return [] }
            case 1: offset += 8
            case 5: offset += 4
            case 2:
                guard let length = varint(), length <= UInt64(bytes.count - offset) else { return [] }
                let end = offset + Int(length)
                result.append((Int(tag >> 3), Data(bytes[offset..<end])))
                offset = end
            default: return []
            }
            guard offset <= bytes.count else { return [] }
        }
        return result
    }

    static func legacy(_ data: Data) -> Credential? {
        for (_, entry) in fields(data).filter({ $0.0 == 1 }) {
            let values = fields(entry)
            guard values.contains(where: { $0.0 == 1 && String(data: $0.1, encoding: .utf8) == "oauthTokenInfoSentinelKey" }),
                  let row = values.first(where: { $0.0 == 2 })?.1,
                  let encoded = fields(row).first(where: { $0.0 == 1 })?.1,
                  let text = String(data: encoded, encoding: .utf8), let info = Data(base64Encoded: text) else { continue }
            let token = fields(info)
            guard let raw = token.first(where: { $0.0 == 3 })?.1, let refresh = String(data: raw, encoding: .utf8), !refresh.isEmpty else { continue }
            return Credential(refresh: refresh, id: token.first(where: { $0.0 == 5 }).flatMap { String(data: $0.1, encoding: .utf8) })
        }
        return nil
    }

    private static func localQuota(_ d: Dependencies) -> QuotaProviderSnapshot {
        let processes = d.command("/bin/ps", ["-axo", "pid=,command="])
        for line in processes.components(separatedBy: .newlines) where line.lowercased().contains("antigravity") && line.contains("language_server") {
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard let pid = parts.first, let flag = parts.firstIndex(of: "--csrf_token"), flag + 1 < parts.count else { continue }
            let ports = d.command("/usr/sbin/lsof", ["-nP", "-a", "-p", pid, "-iTCP", "-sTCP:LISTEN", "-Fn"])
            for entry in ports.components(separatedBy: .newlines) where entry.hasPrefix("n") {
                guard let port = entry.split(separator: ":").last.flatMap({ Int($0) }), (1...65535).contains(port) else { continue }
                for scheme in ["https", "http"] {
                    var req = URLRequest(url: URL(string: "\(scheme)://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary")!)
                    req.httpMethod = "POST"
                    req.httpBody = Data("{\"forceRefresh\":true}".utf8)
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("1", forHTTPHeaderField: "connect-protocol-version")
                    req.setValue(parts[flag + 1], forHTTPHeaderField: "x-codeium-csrf-token")
                    if let (status, data) = d.http(req), status == 200, let root = json(data) {
                        let result = parse(root)
                        if result.kind == .ready { return result }
                    }
                }
            }
        }
        return .unsigned
    }

    private static func post(_ url: String, body: [String: Any], access: String, dependencies: Dependencies) -> [String: Any]? {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        #if arch(arm64)
            let arch = "arm64"
        #else
            let arch = "x64"
        #endif
        req.setValue("antigravity/1.20.5 darwin/\(arch) google-api-nodejs-client/10.3.0", forHTTPHeaderField: "User-Agent")
        guard let (status, data) = dependencies.http(req), (200..<300).contains(status) else { return nil }
        return json(data)
    }

    private static func json(_ data: Data) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
    /// Only the explicitly addressed loopback RPC may use the IDE's self-signed certificate.
    private final class LoopbackTrust: NSObject, URLSessionDelegate {
        func urlSession(_: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void)
        {
            if challenge.protectionSpace.host == "127.0.0.1",
               challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let trust = challenge.protectionSpace.serverTrust
            {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }

    private static func request(_ input: URLRequest) -> (Int, Data)? {
        var req = input
        req.timeoutInterval = 15
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let delegate: URLSessionDelegate? = input.url?.host == "127.0.0.1" ? LoopbackTrust() : nil
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let semaphore = DispatchSemaphore(value: 0)
        var result: (Int, Data)?
        let task = session.dataTask(with: req) { data, response, _ in
            if let data, let response = response as? HTTPURLResponse { result = (response.statusCode, data) }
            semaphore.signal()
        }
        task.resume()
        guard semaphore.wait(timeout: .now() + 20) == .success else { return nil }
        return result
    }

    private static func runCommand(_ executable: String, _ arguments: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        DispatchQueue.global().asyncAfter(deadline: .now() + 6) { if process.isRunning { process.terminate() } }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
