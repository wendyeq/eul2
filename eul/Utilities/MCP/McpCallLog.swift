import Foundation

enum McpCallLog {
    static func append(id: String, tool: String, milliseconds: Int, ok: Bool, error: String?) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        var row: [String: Any] = [
            "time": stamp,
            "id": id,
            "tool": tool,
            "ms": milliseconds,
            "ok": ok,
        ]
        if let error, !error.isEmpty {
            row["error"] = String(error.prefix(200))
        }
        guard var payload = try? JSONSerialization.data(withJSONObject: row) else {
            return
        }
        payload.append(0x0A)
        do {
            try McpPaths.ensureSupportDirectory()
            let url = McpPaths.callLogURL
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: payload)
            }
            truncateIfNeeded()
        } catch {
            return
        }
    }

    static func latestCallDates() -> [String: Date] {
        guard let text = try? String(contentsOf: McpPaths.callLogURL, encoding: .utf8) else {
            return [:]
        }
        let formatter = ISO8601DateFormatter()
        var latest: [String: Date] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard
                let data = String(line).data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let id = json["id"] as? String,
                let stamp = json["time"] as? String,
                let date = formatter.date(from: stamp)
            else {
                continue
            }
            if date > (latest[id] ?? .distantPast) {
                latest[id] = date
            }
        }
        return latest
    }

    private static func truncateIfNeeded() {
        let url = McpPaths.callLogURL
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber,
            size.intValue > McpPaths.maxCallLogBytes,
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return
        }
        let lines = text.split(whereSeparator: \.isNewline)
        let kept = lines.suffix(max(1, lines.count / 2)).joined(separator: "\n") + "\n"
        try? kept.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
