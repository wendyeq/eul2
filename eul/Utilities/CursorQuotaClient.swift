//
//  CursorQuotaClient.swift
//  eul
//

import CommonCrypto
import Foundation
import Security
import SQLite3

enum CursorQuotaClient {
    private static let usageURL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    private static let maxResponseBytes = 5 * 1024 * 1024
    private static let safeStoragePrefix = "cursor-safe-storage:v1:"

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
            return token.isEmpty ? nil : decryptSafeStorage(token)
        }

        let blobBytes = sqlite3_column_bytes(statement, 0)
        if blobBytes > 0, let blob = sqlite3_column_blob(statement, 0) {
            let data = Data(bytes: blob, count: Int(blobBytes))
            if let text = decodeBlobString(data) {
                let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return token.isEmpty ? nil : decryptSafeStorage(token)
            }
        }
        return nil
    }

    private static func decodeBlobString(_ data: Data) -> String? {
        if data.count >= 2,
           data.count.isMultiple(of: 2),
           data[data.startIndex] != 0,
           data[data.index(after: data.startIndex)] == 0,
           let utf16 = String(data: data, encoding: .utf16LittleEndian)
        {
            return utf16
        }
        return String(data: data, encoding: .utf8)
    }

    /// Decrypt Electron safeStorage encrypted token (cursor-safe-storage:v1:...)
    private static func decryptSafeStorage(_ stored: String) -> String? {
        guard stored.hasPrefix(safeStoragePrefix) else {
            return stored // Already plaintext
        }
        let encoded = String(stored.dropFirst(safeStoragePrefix.count))
        guard let ciphertext = Data(base64Encoded: encoded) else {
            return nil
        }

        // Chromium OSCrypt v10/v11 format on macOS:
        // "v10" or "v11" (3 bytes) + AES-128-CBC ciphertext with 16-space IV (0x20 * 16)
        guard ciphertext.count > 3,
              let version = String(data: ciphertext.prefix(3), encoding: .utf8),
              version == "v10" || version == "v11"
        else {
            return nil
        }

        let encrypted = ciphertext.subdata(in: 3..<ciphertext.count)
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)

        guard let key = safeStorageKey(forceRefresh: false) else {
            return nil
        }
        if let decrypted = aesCbcDecrypt(data: encrypted, key: key, iv: iv),
           let token = String(data: decrypted, encoding: .utf8),
           !token.isEmpty
        {
            return token
        }

        // Key may have rotated in Keychain; clear cache and retry once.
        guard let refreshedKey = safeStorageKey(forceRefresh: true),
              refreshedKey != key,
              let decrypted = aesCbcDecrypt(data: encrypted, key: refreshedKey, iv: iv),
              let token = String(data: decrypted, encoding: .utf8),
              !token.isEmpty
        else {
            return nil
        }
        return token
    }

    private static let keychainLock = NSLock()
    private static var cachedSafeStorageKey: Data?
    private static var keychainRefused = false

    /// Get the safeStorage key from macOS Keychain (cached in memory so Keychain is not queried on every poll)
    private static func safeStorageKey(forceRefresh: Bool) -> Data? {
        keychainLock.lock()
        defer { keychainLock.unlock() }

        if forceRefresh {
            cachedSafeStorageKey = nil
        }
        if let cachedSafeStorageKey {
            return cachedSafeStorageKey
        }
        if keychainRefused, !forceRefresh {
            return nil
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Cursor Safe Storage",
            kSecAttrAccount as String: "Cursor Key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let password = result as? Data,
              let key = deriveKey(password: password, salt: Data("saltysalt".utf8), iterations: 1003)
        else {
            if status == errSecAuthFailed || status == errSecUserCanceled || status == errSecInteractionNotAllowed {
                keychainRefused = true
            }
            return nil
        }

        cachedSafeStorageKey = key
        keychainRefused = false
        return key
    }

    private static func deriveKey(password: Data, salt: Data, iterations: Int) -> Data? {
        var derivedKey = Data(count: 16)
        let result = derivedKey.withUnsafeMutableBytes { derivedKeyPtr in
            salt.withUnsafeBytes { saltPtr in
                password.withUnsafeBytes { passwordPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPtr.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        UInt32(iterations),
                        derivedKeyPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        16
                    )
                }
            }
        }
        return result == kCCSuccess ? derivedKey : nil
    }

    private static func aesCbcDecrypt(data: Data, key: Data, iv: Data) -> Data? {
        guard key.count == kCCKeySizeAES128 || key.count == kCCKeySizeAES256,
              iv.count == kCCBlockSizeAES128
        else {
            return nil
        }
        var decrypted = Data(count: data.count + kCCBlockSizeAES128)
        var decryptedLength = 0
        let dataCount = data.count
        let decryptedCount = decrypted.count
        let result = decrypted.withUnsafeMutableBytes { decryptedPtr in
            data.withUnsafeBytes { dataPtr in
                iv.withUnsafeBytes { ivPtr in
                    key.withUnsafeBytes { keyPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            dataPtr.baseAddress, dataCount,
                            decryptedPtr.baseAddress, decryptedCount,
                            &decryptedLength
                        )
                    }
                }
            }
        }
        guard result == kCCSuccess else {
            return nil
        }
        return decrypted.prefix(decryptedLength)
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
