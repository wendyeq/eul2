//
//  GrokQuotaClient.swift
//  eul
//

import Darwin
import Foundation

enum GrokQuotaClient {
    private static let creditsURL = URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig")!
    private static let tokenURL = URL(string: "https://auth.x.ai/oauth2/token")!
    private static let emptyGrpcFrame = Data([0x00, 0x00, 0x00, 0x00, 0x00])
    private static let maxResponseBytes = 2 * 1024 * 1024
    private static let refreshSkew: TimeInterval = 60

    private struct Credential {
        let entryKey: String
        var accessToken: String
        var refreshToken: String
        let clientId: String
        var expiresAt: String

        var canRefresh: Bool {
            !refreshToken.isEmpty && !clientId.isEmpty
        }

        var needsRefresh: Bool {
            accessToken.isEmpty || GrokQuotaClient.isExpired(expiresAt)
        }
    }

    static func fetchSync() -> QuotaProviderSnapshot {
        guard var credential = readCredential() else {
            return .unsigned
        }

        var didRefresh = false
        if credential.needsRefresh, credential.canRefresh {
            if applyRefresh(&credential) {
                didRefresh = true
            } else if credential.accessToken.isEmpty {
                return .unsigned
            }
        }
        if credential.accessToken.isEmpty {
            return .unsigned
        }

        var result = requestCredits(token: credential.accessToken)
        if isUnauthenticated(result), !didRefresh, credential.canRefresh {
            if applyRefresh(&credential) {
                result = requestCredits(token: credential.accessToken)
            }
        }
        return snapshot(from: result)
    }

    private static func authURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/auth.json")
    }

    private static func readCredential() -> Credential? {
        let url = authURL()
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        var preferred: Credential?
        var fallback: Credential?
        for (key, raw) in root {
            guard let entry = raw as? [String: Any] else {
                continue
            }
            let access = string(entry["key"]) ?? string(entry["access_token"]) ?? ""
            let refresh = string(entry["refresh_token"]) ?? ""
            if access.isEmpty, refresh.isEmpty {
                continue
            }
            let credential = Credential(
                entryKey: key,
                accessToken: access,
                refreshToken: refresh,
                clientId: string(entry["oidc_client_id"]) ?? "",
                expiresAt: string(entry["expires_at"]) ?? ""
            )
            if key.hasPrefix("https://auth.x.ai::") {
                preferred = credential
            } else if fallback == nil {
                fallback = credential
            }
        }
        return preferred ?? fallback
    }

    private static func requestCredits(token: String) -> QuotaHTTP.Result {
        var request = URLRequest(url: creditsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Content-Type")
        request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Accept")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "User-Agent")
        request.setValue("1", forHTTPHeaderField: "x-grpc-web")
        request.httpBody = emptyGrpcFrame
        return QuotaHTTP.request(request, maxBytes: maxResponseBytes)
    }

    private static func snapshot(from result: QuotaHTTP.Result) -> QuotaProviderSnapshot {
        if isUnauthenticated(result) {
            return .unsigned
        }
        guard result.ok, let data = result.data, let parsed = GrokCreditsParser.parse(data) else {
            return .failedEmpty
        }
        return QuotaProviderSnapshot(kind: .ready, meters: [parsed])
    }

    private static func isUnauthenticated(_ result: QuotaHTTP.Result) -> Bool {
        if result.status == 401 || result.status == 403 {
            return true
        }
        return grpcStatus(result) == 16
    }

    private static func grpcStatus(_ result: QuotaHTTP.Result) -> Int? {
        if let raw = result.header("grpc-status") {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Int(trimmed) {
                return value
            }
        }
        guard let data = result.data else {
            return nil
        }
        return GrokCreditsParser.grpcStatus(fromTrailers: data)
    }

    @discardableResult
    private static func applyRefresh(_ credential: inout Credential) -> Bool {
        guard let refreshed = refreshAccessToken(credential) else {
            return false
        }
        credential.accessToken = refreshed.accessToken
        credential.refreshToken = refreshed.refreshToken
        credential.expiresAt = refreshed.expiresAt
        writeAuthUpdate(credential)
        return true
    }

    private static func refreshAccessToken(_ credential: Credential) -> (accessToken: String, refreshToken: String, expiresAt: String)? {
        guard credential.canRefresh else {
            return nil
        }

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: credential.refreshToken),
            URLQueryItem(name: "client_id", value: credential.clientId),
        ]
        guard let body = components.percentEncodedQuery?.data(using: .utf8) else {
            return nil
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        let result = QuotaHTTP.request(request, maxBytes: maxResponseBytes)
        guard result.ok, let data = result.data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        guard let accessToken = string(json["access_token"]) else {
            return nil
        }
        let refreshToken = string(json["refresh_token"]) ?? credential.refreshToken
        let expiresAt: String
        if let expiresIn = QuotaTimestamp.number(fromAPI: json["expires_in"]), expiresIn > 0 {
            expiresAt = iso8601String(from: Date().addingTimeInterval(expiresIn))
        } else {
            expiresAt = credential.expiresAt
        }
        return (accessToken, refreshToken, expiresAt)
    }

    private static func writeAuthUpdate(_ credential: Credential) {
        let url = authURL()
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }
        var root = raw
        var entry = root[credential.entryKey] as? [String: Any] ?? [:]
        entry["key"] = credential.accessToken
        entry["refresh_token"] = credential.refreshToken
        if !credential.expiresAt.isEmpty {
            entry["expires_at"] = credential.expiresAt
        }
        root[credential.entryKey] = entry
        guard let payload = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .withoutEscapingSlashes]),
              var text = String(data: payload, encoding: .utf8)
        else {
            return
        }
        if !text.hasSuffix("\n") {
            text.append("\n")
        }
        guard let fileData = text.data(using: .utf8) else {
            return
        }

        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent("auth.json.tmp-eul2-\(ProcessInfo.processInfo.processIdentifier)")
        do {
            try fileData.write(to: tmp, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
            let renamed = tmp.path.withCString { tmpPath in
                url.path.withCString { destPath in
                    rename(tmpPath, destPath) == 0
                }
            }
            if !renamed {
                try? FileManager.default.removeItem(at: tmp)
                return
            }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    private static func isExpired(_ raw: String) -> Bool {
        guard let date = parseExpiresAt(raw) else {
            return false
        }
        return date.timeIntervalSinceNow <= refreshSkew
    }

    private static func parseExpiresAt(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: raw)
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func string(_ value: Any?) -> String? {
        guard let string = value as? String else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum GrokCreditsParser {
    static func grpcStatus(fromTrailers body: Data) -> Int? {
        var i = 0
        while i + 5 <= body.count {
            let flags = body[i]
            let length = Int(body[i + 1]) << 24
                | Int(body[i + 2]) << 16
                | Int(body[i + 3]) << 8
                | Int(body[i + 4])
            i += 5
            guard i + length <= body.count else {
                break
            }
            let slice = body.subdata(in: i..<(i + length))
            i += length
            guard flags & 0x80 != 0 else {
                continue
            }
            guard let text = String(data: slice, encoding: .utf8) else {
                continue
            }
            for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2 else {
                    continue
                }
                let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard name == "grpc-status" else {
                    continue
                }
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if let status = Int(value) {
                    return status
                }
            }
        }
        return nil
    }

    static func parse(_ body: Data) -> QuotaMeter? {
        guard let message = extractGrpcMessage(body) else {
            return nil
        }
        guard let outer = walkProto(message) else {
            return nil
        }
        var configBuf = message
        for field in outer {
            if field.number == 1, field.wireType == 2, let bytes = field.bytes, !bytes.isEmpty {
                configBuf = bytes
                break
            }
        }
        guard let fields = walkProto(configBuf) else {
            return nil
        }

        var usedPercent: Double?
        var windowStart: Date?
        var windowEnd: Date?

        for field in fields {
            if field.number == 1, field.wireType == 5, let bytes = field.bytes {
                guard let value = readFloat32(bytes) else {
                    return nil
                }
                usedPercent = Double(value)
            } else if field.number == 1 {
                return nil
            } else if field.number == 4 || field.number == 5 {
                guard field.wireType == 2, let bytes = field.bytes, let timestamp = readTimestamp(bytes) else {
                    return nil
                }
                if field.number == 4 {
                    windowStart = timestamp
                } else {
                    windowEnd = timestamp
                }
            }
        }

        let percent: Double
        if let usedPercent {
            percent = QuotaTimestamp.clampPercent(usedPercent)
        } else if windowEnd != nil {
            percent = 0
        } else {
            return nil
        }
        return QuotaMeter(
            id: "weekly",
            labelKey: "quota.grok.credits",
            usedPercent: percent,
            windowStart: windowStart,
            resetsAt: windowEnd
        )
    }

    private struct ProtoField {
        let number: UInt32
        let wireType: UInt32
        let bytes: Data?
        let varint: UInt64?
    }

    private static func extractGrpcMessage(_ body: Data) -> Data? {
        guard body.count >= 5 else {
            return nil
        }
        var i = 0
        while i + 5 <= body.count {
            let flags = body[i]
            let length = Int(body[i + 1]) << 24
                | Int(body[i + 2]) << 16
                | Int(body[i + 3]) << 8
                | Int(body[i + 4])
            i += 5
            guard i + length <= body.count else {
                break
            }
            let slice = body.subdata(in: i..<(i + length))
            i += length
            if flags & 0x80 == 0 {
                return slice
            }
        }
        return nil
    }

    private static func walkProto(_ data: Data) -> [ProtoField]? {
        var fields: [ProtoField] = []
        var i = 0
        while i < data.count {
            guard let key = decodeVarint(data, offset: i) else {
                return nil
            }
            i = key.offset
            if key.value > 0xFFFF_FFFF {
                return nil
            }
            let field = UInt32(key.value >> 3)
            let wireType = UInt32(key.value & 7)
            if field == 0 {
                return nil
            }
            switch wireType {
            case 0:
                guard let value = decodeVarint(data, offset: i) else {
                    return nil
                }
                i = value.offset
                fields.append(ProtoField(number: field, wireType: wireType, bytes: nil, varint: value.value))
            case 1:
                guard i + 8 <= data.count else {
                    return nil
                }
                fields.append(ProtoField(number: field, wireType: wireType, bytes: data.subdata(in: i..<(i + 8)), varint: nil))
                i += 8
            case 2:
                guard let length = decodeVarint(data, offset: i) else {
                    return nil
                }
                i = length.offset
                guard i + Int(length.value) <= data.count else {
                    return nil
                }
                let end = i + Int(length.value)
                fields.append(ProtoField(number: field, wireType: wireType, bytes: data.subdata(in: i..<end), varint: nil))
                i = end
            case 5:
                guard i + 4 <= data.count else {
                    return nil
                }
                fields.append(ProtoField(number: field, wireType: wireType, bytes: data.subdata(in: i..<(i + 4)), varint: nil))
                i += 4
            default:
                return nil
            }
        }
        return fields
    }

    private static func decodeVarint(_ data: Data, offset: Int) -> (value: UInt64, offset: Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var i = offset
        while i < data.count {
            let byte = data[i]
            i += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return (result, i)
            }
            shift += 7
            if shift > 63 {
                return nil
            }
        }
        return nil
    }

    private static func readFloat32(_ data: Data) -> Float? {
        guard data.count >= 4 else {
            return nil
        }
        var bits: UInt32 = 0
        _ = withUnsafeMutableBytes(of: &bits) { dest in
            data.copyBytes(to: dest, count: 4)
        }
        bits = UInt32(littleEndian: bits)
        let value = Float(bitPattern: bits)
        return value.isFinite ? value : nil
    }

    private static func readTimestamp(_ data: Data) -> Date? {
        guard !data.isEmpty, let fields = walkProto(data) else {
            return nil
        }
        var seconds: Int64?
        var nanos: Int64 = 0
        for field in fields {
            guard field.wireType == 0, let varint = field.varint else {
                continue
            }
            if field.number == 1 {
                seconds = Int64(bitPattern: varint)
            } else if field.number == 2 {
                nanos = Int64(bitPattern: varint)
            }
        }
        guard let seconds,
              seconds >= -62_135_596_800,
              seconds <= 253_402_300_799,
              nanos >= 0,
              nanos <= 999_999_999
        else {
            return nil
        }
        let millis = Double(seconds) * 1000 + Double(nanos / 1_000_000)
        return Date(timeIntervalSince1970: millis / 1000)
    }
}
