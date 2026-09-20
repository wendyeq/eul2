import Foundation
import Logging
import MCP

struct McpUpstreamClient {
    let id: String
    let client: Client
    let process: Process?
}

enum McpUpstream {
    static func connect(_ entry: McpServerEntry, onProcessExit: (@Sendable (Process) -> Void)? = nil) async throws -> McpUpstreamClient {
        let client = Client(name: "eul2", version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.2.0")
        if entry.isRemote {
            guard let raw = entry.url, let url = URL(string: raw) else {
                throw MCPError.invalidParams("invalid url for \(entry.id)")
            }
            let transport = HTTPClientTransport(endpoint: url, streaming: true) { request in
                var modified = request
                for (key, value) in entry.headers {
                    modified.setValue(value, forHTTPHeaderField: key)
                }
                return modified
            }
            _ = try await client.connect(transport: transport)
            return McpUpstreamClient(id: entry.id, client: client, process: nil)
        }
        guard let command = entry.command, !command.isEmpty else {
            throw MCPError.invalidParams("missing command for \(entry.id)")
        }
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.executableURL = URL(fileURLWithPath: McpPaths.resolveExecutable(command))
        process.arguments = entry.args
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = McpPaths.loginPath
        for (key, value) in entry.env {
            environment[key] = value
        }
        process.environment = environment
        let cwd = entry.cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cwd, !cwd.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        } else {
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        }
        let transport = ProcessStdioTransport(
            process: process,
            stdinHandle: stdin.fileHandleForWriting,
            stdoutHandle: stdout.fileHandleForReading,
            onExit: {
                onProcessExit?(process)
            }
        )
        var connected = false
        defer {
            if !connected {
                process.terminationHandler = nil
                if process.isRunning {
                    process.terminate()
                }
            }
        }
        _ = try await client.connect(transport: transport)
        connected = true
        return McpUpstreamClient(id: entry.id, client: client, process: process)
    }
}
