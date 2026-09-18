//
//  GrokQuotaClient.swift
//  eul
//

import Foundation

enum GrokQuotaClient {
    private static let creditsURL = URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig")!
    private static let emptyGrpcFrame = Data([0x00, 0x00, 0x00, 0x00, 0x00])
    private static let maxResponseBytes = 2 * 1024 * 1024

    static func fetchSync() -> QuotaProviderSnapshot {
        guard let token = readCredential() else {
            return .unsigned
        }
        // Have a token: always probe the API. Local expires_at alone must not
        // flash a login prompt; 401/403 is what confirms the credential is dead.
        return fetchCredits(token: token)
    }

    private static func authURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".grok/auth.json")
    }

    private static func readCredential() -> String? {
        let url = authURL()
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        var preferred: String?
        var fallback: String?
        for (key, raw) in root {
            guard let entry = raw as? [String: Any] else {
                continue
            }
            guard let token = string(entry["key"]) ?? string(entry["access_token"]) else {
                continue
            }
            if key.hasPrefix("https://auth.x.ai::") {
                preferred = token
            } else if fallback == nil {
                fallback = token
            }
        }
        return preferred ?? fallback
    }

    private static func fetchCredits(token: String) -> QuotaProviderSnapshot {
        var request = URLRequest(url: creditsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Content-Type")
        request.setValue("application/grpc-web+proto", forHTTPHeaderField: "Accept")
        request.setValue("xai-grok-cli", forHTTPHeaderField: "User-Agent")
        request.setValue("1", forHTTPHeaderField: "x-grpc-web")
        request.httpBody = emptyGrpcFrame

        let result = QuotaHTTP.request(request, maxBytes: maxResponseBytes)
        if result.status == 401 || result.status == 403 {
            return .unsigned
        }
        guard result.ok, let data = result.data, let parsed = GrokCreditsParser.parse(data) else {
            return .failedEmpty
        }
        return QuotaProviderSnapshot(kind: .ready, meters: [parsed])
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
