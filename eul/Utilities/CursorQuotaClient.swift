//
//  CursorQuotaClient.swift
//  eul
//

import Foundation
import SQLite3

enum CursorQuotaClient {
    private static let usageURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    private static let maxResponseBytes = 5 * 1024 * 1024

    static func fetchSync() -> QuotaProviderSnapshot {
        guard let token = readAccessToken(), !token.isEmpty else {
            return .unsigned
        }
        return fetchUsage(token: token)
    }

    private static func stateDatabaseURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    private static func readAccessToken() -> String? {
        let path = stateDatabaseURL().path
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            if db != nil {
                sqlite3_close(db)
            }
            return nil
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        if let cString = sqlite3_column_text(statement, 0) {
            let token = String(cString: cString).trimmingCharacters(in: .whitespacesAndNewlines)
            return token.isEmpty ? nil : token
        }

        let blobBytes = sqlite3_column_bytes(statement, 0)
        if blobBytes > 0, let blob = sqlite3_column_blob(statement, 0) {
            let data = Data(bytes: blob, count: Int(blobBytes))
            if let utf8 = String(data: data, encoding: .utf8) {
                let token = utf8.trimmingCharacters(in: .whitespacesAndNewlines)
                return token.isEmpty ? nil : token
            }
        }
        return nil
    }

    private static func fetchUsage(token: String) -> QuotaProviderSnapshot {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Cursor/0.45.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)

        let result = QuotaHTTP.request(request, maxBytes: maxResponseBytes)
        if result.status == 401 || result.status == 403 {
            return .unsigned
        }
        guard result.ok, let data = result.data else {
            return .failedEmpty
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .failedEmpty
        }

        guard let planUsage = json["planUsage"] as? [String: Any] else {
            return .failedEmpty
        }

        let autoPercent = QuotaTimestamp.clampPercent(QuotaTimestamp.number(fromAPI: planUsage["autoPercentUsed"]) ?? 0)
        let apiPercent = QuotaTimestamp.clampPercent(QuotaTimestamp.number(fromAPI: planUsage["apiPercentUsed"]) ?? 0)
        let windowStart = QuotaTimestamp.date(fromAPI: json["billingCycleStart"])
        let resetAt = QuotaTimestamp.date(fromAPI: json["billingCycleEnd"])
        return QuotaProviderSnapshot(
            kind: .ready,
            meters: [
                QuotaMeter(
                    id: "auto",
                    labelKey: "quota.cursor.auto",
                    usedPercent: autoPercent,
                    windowStart: windowStart,
                    resetsAt: resetAt
                ),
                QuotaMeter(
                    id: "api",
                    labelKey: "quota.cursor.api",
                    usedPercent: apiPercent,
                    windowStart: windowStart,
                    resetsAt: resetAt
                ),
            ]
        )
    }
}

enum QuotaHTTP {
    struct Result {
        let ok: Bool
        let status: Int
        let data: Data?
        let headers: [String: String]

        func header(_ name: String) -> String? {
            headers[name.lowercased()]
        }
    }

    static func request(_ request: URLRequest, maxBytes: Int) -> Result {
        let semaphore = DispatchSemaphore(value: 0)
        var captured = Result(ok: false, status: 0, data: nil, headers: [:])
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            let http = response as? HTTPURLResponse
            let status = http?.statusCode ?? 0
            var headers: [String: String] = [:]
            if let http {
                for (key, value) in http.allHeaderFields {
                    headers[String(describing: key).lowercased()] = String(describing: value)
                }
            }
            if let data, data.count > maxBytes {
                captured = Result(ok: false, status: status, data: nil, headers: headers)
            } else {
                captured = Result(ok: status >= 200 && status < 300, status: status, data: data, headers: headers)
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + request.timeoutInterval + 2)
        return captured
    }
}
