import Foundation

extension NSNotification.Name {
    static let mcpHubDidChange = NSNotification.Name("eul2.mcpHubDidChange")
}

enum McpPaths {
    static let defaultPort = 18732
    static let maxCallLogBytes = 2 * 1024 * 1024

    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/eul2", isDirectory: true)
    }

    static var catalogURL: URL {
        supportDirectory.appendingPathComponent("mcp-catalog.json")
    }

    static var callLogURL: URL {
        supportDirectory.appendingPathComponent("mcp-calls.jsonl")
    }

    static func ensureSupportDirectory() throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
    }

    static func writeAtomic(_ data: Data, to url: URL, posixPermissions: Int? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp, options: .atomic)
        if let posixPermissions {
            try FileManager.default.setAttributes([.posixPermissions: posixPermissions], ofItemAtPath: tmp.path)
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        if let posixPermissions {
            try? FileManager.default.setAttributes([.posixPermissions: posixPermissions], ofItemAtPath: url.path)
        }
    }

    static var loginPath: String {
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        let current = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var parts = extra
        for item in current.split(separator: ":").map(String.init) where !parts.contains(item) {
            parts.append(item)
        }
        return parts.joined(separator: ":")
    }

    static func resolveExecutable(_ command: String) -> String {
        if command.contains("/") {
            return command
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.environment = ["PATH": loginPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return command
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? command : path
    }
}
