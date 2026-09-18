//
//  CodexQuotaClient.swift
//  eul
//
//  Reads Codex subscription windows via local `codex app-server` JSON-RPC
//  (same path CodexBar uses for CLI RPC).
//

import Foundation

enum CodexQuotaClient {
    private static let requestTimeout: TimeInterval = 15

    static func fetchSync() -> QuotaProviderSnapshot {
        guard hasAuthFile() else {
            return .unsigned
        }
        guard let executable = resolveCodexExecutable() else {
            return .failedEmpty
        }
        return runAppServerProbe(executable: executable)
    }

    private static func authURL() -> URL {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("auth.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
    }

    private static func hasAuthFile() -> Bool {
        let url = authURL()
        guard
            let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        if let tokens = root["tokens"] as? [String: Any], hasAccessToken(tokens) {
            return true
        }
        return hasAccessToken(root)
    }

    private static func hasAccessToken(_ root: [String: Any]) -> Bool {
        let access = (root["access_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !access.isEmpty
    }

    private static func resolveCodexExecutable() -> String? {
        let fileManager = FileManager.default
        if let path = which("codex"), fileManager.isExecutableFile(atPath: path) {
            return path
        }
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0) }
    }

    private static func which(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    private static func runAppServerProbe(executable: String) -> QuotaProviderSnapshot {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-s", "read-only", "-a", "never", "app-server"]
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .failedEmpty
        }

        defer {
            terminate(process)
        }

        let writer = stdin.fileHandleForWriting
        let reader = stdout.fileHandleForReading

        guard
            send(writer, ["method": "initialize", "id": 1, "params": [
                "clientInfo": [
                    "name": "eul2",
                    "title": "eul2",
                    "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0",
                ],
            ]]),
            let _ = waitForResponse(reader: reader, id: 1, process: process),
            send(writer, ["method": "initialized", "params": [:] as [String: Any]]),
            send(writer, ["method": "account/rateLimits/read", "id": 2, "params": [:] as [String: Any]]),
            let rateLimits = waitForResponse(reader: reader, id: 2, process: process)
        else {
            return .failedEmpty
        }

        if let error = rateLimits["error"] as? [String: Any] {
            let message = ((error["message"] as? String) ?? "").lowercased()
            if message.contains("auth") || message.contains("login") || message.contains("unauthorized") {
                return .unsigned
            }
            return .failedEmpty
        }

        guard let result = rateLimits["result"] as? [String: Any] else {
            return .failedEmpty
        }
        return parseRateLimits(result)
    }

    private static func parseRateLimits(_ result: [String: Any]) -> QuotaProviderSnapshot {
        let limits: [String: Any]
        if let byId = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = byId["codex"] as? [String: Any]
        {
            limits = codex
        } else if let rateLimits = result["rateLimits"] as? [String: Any] {
            limits = rateLimits
        } else {
            return .failedEmpty
        }

        // Some accounts have no 5h bucket: primary may be the weekly window and
        // secondary null, or primary null with only secondary. Label by duration,
        // never assume primary == 5h / secondary == weekly.
        var meters: [QuotaMeter] = []
        if let primary = limits["primary"] as? [String: Any],
           let meter = meter(slot: "primary", window: primary)
        {
            meters.append(meter)
        }
        if let secondary = limits["secondary"] as? [String: Any],
           let meter = meter(slot: "secondary", window: secondary)
        {
            meters.append(meter)
        }
        guard !meters.isEmpty else {
            return .failedEmpty
        }
        return QuotaProviderSnapshot(kind: .ready, meters: meters)
    }

    private static func meter(slot: String, window: [String: Any]) -> QuotaMeter? {
        guard let usedPercent = QuotaTimestamp.number(fromAPI: window["usedPercent"]) else {
            return nil
        }
        let durationMins = QuotaTimestamp.number(fromAPI: window["windowDurationMins"]) ?? 0
        guard durationMins > 0 else {
            return nil
        }
        let resetsAt = QuotaTimestamp.number(fromAPI: window["resetsAt"]).map { Date(timeIntervalSince1970: $0) }
        return QuotaMeter(
            id: "\(slot)-\(Int(durationMins))",
            labelKey: labelKey(forDurationMinutes: durationMins),
            usedPercent: QuotaTimestamp.clampPercent(usedPercent),
            windowStart: resetsAt?.addingTimeInterval(-durationMins * 60),
            resetsAt: resetsAt
        )
    }

    /// Match CodexBar: name the window by its length, not by primary/secondary slot.
    private static func labelKey(forDurationMinutes mins: Double) -> String {
        if abs(mins - 300) <= 60 {
            return "quota.codex.primary"
        }
        if abs(mins - 10080) <= 720 {
            return "quota.codex.weekly"
        }
        if abs(mins - 1440) <= 120 {
            return "quota.codex.daily"
        }
        if abs(mins - 43200) <= 1440 {
            return "quota.codex.monthly"
        }
        if mins >= 1440 {
            return "quota.codex.weekly"
        }
        return "quota.codex.primary"
    }

    @discardableResult
    private static func send(_ writer: FileHandle, _ object: [String: Any]) -> Bool {
        guard JSONSerialization.isValidJSONObject(object),
              var payload = try? JSONSerialization.data(withJSONObject: object, options: [])
        else {
            return false
        }
        payload.append(0x0A)
        do {
            try writer.write(contentsOf: payload)
            return true
        } catch {
            return false
        }
    }

    private static func waitForResponse(reader: FileHandle, id: Int, process: Process) -> [String: Any]? {
        let deadline = Date().addingTimeInterval(requestTimeout)
        var buffer = Data()
        while Date() < deadline {
            if !process.isRunning, buffer.isEmpty {
                return nil
            }
            let chunk = reader.availableData
            if chunk.isEmpty {
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            buffer.append(chunk)
            while let range = buffer.range(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                guard !lineData.isEmpty,
                      let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                else {
                    continue
                }
                let responseId = (object["id"] as? Int) ?? (object["id"] as? NSNumber)?.intValue
                if responseId == id {
                    return object
                }
            }
        }
        return nil
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else {
            return
        }
        process.terminate()
        let deadline = Date().addingTimeInterval(1.5)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
