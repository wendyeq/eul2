import Foundation

enum McpAgentWriter {
    static let serverID = "eul2-mcp"

    struct Result {
        var updated: [String]
        var failed: [String]
    }

    static func connectAgents(executable: String, port: Int) -> Result {
        var updated: [String] = []
        var failed: [String] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        func attempt(_ name: String, _ work: () throws -> Void) {
            do {
                try work()
                updated.append(name)
            } catch {
                failed.append(name)
            }
        }
        attempt("Cursor") {
            try upsertJSON(url: home.appendingPathComponent(".cursor/mcp.json"), executable: executable)
        }
        attempt("Claude Desktop") {
            try upsertJSON(
                url: home.appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json"),
                executable: executable
            )
        }
        attempt("Claude Code") {
            try upsertJSON(url: home.appendingPathComponent(".claude.json"), executable: executable)
        }
        let httpURL = "http://127.0.0.1:\(port)/mcp"
        attempt("Codex") {
            try upsertTOML(url: home.appendingPathComponent(".codex/config.toml"), httpURL: httpURL)
        }
        attempt("Grok") {
            try upsertTOML(url: home.appendingPathComponent(".grok/config.toml"), httpURL: httpURL)
        }
        return Result(updated: updated, failed: failed)
    }

    private static func upsertJSON(url: URL, executable: String) throws {
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            root = parsed
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers[serverID] = [
            "command": executable,
            "args": ["mcp-connect"],
        ]
        root["mcpServers"] = servers
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try McpPaths.writeAtomic(data, to: url)
    }

    private static func upsertTOML(url: URL, httpURL: String) throws {
        var content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let escaped = NSRegularExpression.escapedPattern(for: serverID)
        let pattern = "\\[mcp_servers\\.\(escaped)\\][\\s\\S]*?(?=\\n\\[|\\z)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(content.startIndex..., in: content)
            content = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
        }
        let block = """

        [mcp_servers.\(serverID)]
        url = "\(httpURL)"
        startup_timeout_sec = 120
        """
        content = content.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + block + "\n"
        try McpPaths.writeAtomic(Data(content.utf8), to: url)
    }
}
