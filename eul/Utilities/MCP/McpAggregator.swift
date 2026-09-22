import Foundation
import MCP

actor McpAggregator {
    private var clients: [String: McpUpstreamClient] = [:]
    private var lastCall: [String: Date] = [:]
    private var lastError: [String: String] = [:]
    private var onActivity: (@Sendable () -> Void)?

    func setOnActivity(_ handler: (@Sendable () -> Void)?) {
        onActivity = handler
    }

    func replaceClients(_ next: [McpUpstreamClient]) {
        let incoming = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) })
        for (id, existing) in clients {
            if let updated = incoming[id] {
                if existing.process !== updated.process {
                    stopProcess(existing.process)
                }
            } else {
                stopProcess(existing.process)
            }
        }
        clients = incoming
    }

    func client(id: String) -> McpUpstreamClient? {
        clients[id]
    }

    func allClients() -> [McpUpstreamClient] {
        Array(clients.values)
    }

    func putClient(_ client: McpUpstreamClient) {
        if let existing = clients[client.id], existing.process !== client.process {
            stopProcess(existing.process)
        }
        clients[client.id] = client
    }

    func removeClient(id: String) {
        if let existing = clients.removeValue(forKey: id) {
            stopProcess(existing.process)
        }
    }

    func markFailed(id: String, message: String) {
        lastError[id] = String(message.prefix(200))
    }

    func clearFailed(id: String) {
        lastError[id] = nil
    }

    private func stopProcess(_ process: Process?) {
        guard let process else {
            return
        }
        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }

    func snapshot(catalog: McpCatalog, connecting: Set<String>) -> [McpServerStatus] {
        let logged = McpCallLog.latestCallDates()
        return catalog.servers.map { entry in
            McpServerStatus(
                id: entry.id,
                enabled: entry.enabled,
                lastCallAt: lastCall[entry.id] ?? logged[entry.id],
                lastError: lastError[entry.id],
                connected: clients[entry.id] != nil,
                connecting: connecting.contains(entry.id)
            )
        }
    }

    func listTools() async throws -> [Tool] {
        var tools: [Tool] = []
        for (id, upstream) in clients {
            do {
                let (listed, _) = try await upstream.client.listTools()
                for tool in listed {
                    tools.append(
                        Tool(
                            name: qualify(id, tool.name),
                            description: tool.description,
                            inputSchema: tool.inputSchema
                        )
                    )
                }
            } catch {
                markFailed(id: id, message: error.localizedDescription)
            }
        }
        return tools
    }

    func callTool(name: String, arguments: [String: Value]?) async throws -> CallTool.Result {
        let (id, original) = Self.splitPrefixed(name)
        guard let upstream = clients[id] else {
            throw MCPError.invalidParams("unknown server for tool \(name)")
        }
        let started = Date()
        do {
            let (content, isError) = try await upstream.client.callTool(name: original, arguments: arguments)
            lastCall[id] = Date()
            if isError == true {
                lastError[id] = "tool error"
                record(id: id, tool: name, started: started, ok: false, error: "tool error")
            } else {
                lastError[id] = nil
                record(id: id, tool: name, started: started, ok: true, error: nil)
            }
            return .init(content: content, isError: isError)
        } catch {
            lastError[id] = error.localizedDescription
            record(id: id, tool: name, started: started, ok: false, error: error.localizedDescription)
            throw error
        }
    }

    func listResources() async throws -> [Resource] {
        var resources: [Resource] = []
        for (id, upstream) in clients {
            do {
                let (listed, _) = try await upstream.client.listResources()
                for resource in listed {
                    resources.append(
                        Resource(
                            name: qualify(id, resource.name),
                            uri: "eul2://\(id)/\(resource.uri)",
                            description: resource.description,
                            mimeType: resource.mimeType
                        )
                    )
                }
            } catch {}
        }
        return resources
    }

    func readResource(uri: String) async throws -> ReadResource.Result {
        let (id, original) = Self.splitResourceURI(uri)
        guard let upstream = clients[id] else {
            throw MCPError.invalidParams("unknown resource \(uri)")
        }
        let contents = try await upstream.client.readResource(uri: original)
        return .init(contents: contents)
    }

    func listPrompts() async throws -> [Prompt] {
        var prompts: [Prompt] = []
        for (id, upstream) in clients {
            do {
                let (listed, _) = try await upstream.client.listPrompts()
                for prompt in listed {
                    prompts.append(
                        Prompt(
                            name: qualify(id, prompt.name),
                            description: prompt.description,
                            arguments: prompt.arguments
                        )
                    )
                }
            } catch {}
        }
        return prompts
    }

    func getPrompt(name: String, arguments: [String: String]?) async throws -> GetPrompt.Result {
        let (id, original) = Self.splitPrefixed(name)
        guard let upstream = clients[id] else {
            throw MCPError.invalidParams("unknown prompt \(name)")
        }
        let (description, messages) = try await upstream.client.getPrompt(name: original, arguments: arguments)
        return .init(description: description, messages: messages)
    }

    private func record(id: String, tool: String, started: Date, ok: Bool, error: String?) {
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        McpCallLog.append(id: id, tool: tool, milliseconds: ms, ok: ok, error: error)
        onActivity?()
    }

    private static let nameSeparator = "--"

    private func qualify(_ id: String, _ name: String) -> String {
        "\(id)\(Self.nameSeparator)\(name)"
    }

    static func splitPrefixed(_ name: String) -> (String, String) {
        guard let range = name.range(of: nameSeparator) else {
            return ("", name)
        }
        return (String(name[..<range.lowerBound]), String(name[range.upperBound...]))
    }

    static func splitResourceURI(_ uri: String) -> (String, String) {
        guard uri.hasPrefix("eul2://") else {
            return splitPrefixed(uri)
        }
        let rest = String(uri.dropFirst("eul2://".count))
        guard let slash = rest.firstIndex(of: "/") else {
            return (rest, rest)
        }
        let id = String(rest[..<slash])
        let original = String(rest[rest.index(after: slash)...])
        return (id, original.removingPercentEncoding ?? original)
    }
}

enum McpElapsedUnit: Equatable {
    case seconds(Int)
    case minutes(Int)
    case hours(Int)
    case days(Int)
    case weeks(Int)
    case months(Int)
    case years(Int)

    var localizationKey: String {
        switch self {
        case .seconds: return "mcp.seconds_ago"
        case .minutes: return "mcp.minutes_ago"
        case .hours: return "mcp.hours_ago"
        case .days: return "mcp.days_ago"
        case .weeks: return "mcp.weeks_ago"
        case .months: return "mcp.months_ago"
        case .years: return "mcp.years_ago"
        }
    }

    var count: Int {
        switch self {
        case let .seconds(count), let .minutes(count), let .hours(count), let .days(count),
             let .weeks(count), let .months(count), let .years(count):
            return count
        }
    }

    // Cutovers match RelativeDateTimeFormatter.UnitsStyle.abbreviated.
    static func from(seconds raw: Int) -> McpElapsedUnit {
        let seconds = max(0, raw)
        if seconds < 60 {
            return .seconds(seconds)
        }
        if seconds < 3600 {
            return .minutes(seconds / 60)
        }
        if seconds < 86400 {
            return .hours(seconds / 3600)
        }
        let days = seconds / 86400
        if days < 7 {
            return .days(days)
        }
        if days < 31 {
            return .weeks(days / 7)
        }
        if days < 365 {
            return .months(days / 31)
        }
        return .years(days / 365)
    }
}

struct McpServerStatus: Identifiable, Equatable {
    var id: String
    var enabled: Bool
    var lastCallAt: Date?
    var lastError: String?
    var connected: Bool
    var connecting: Bool

    func statusText(now: Date, showsErrorDetail: Bool = false) -> String {
        if connecting {
            return "mcp.connecting".localized()
        }
        if let lastError, !lastError.isEmpty {
            if showsErrorDetail {
                return "mcp.failed".localized() + " · \(lastError)"
            }
            return "mcp.failed".localized()
        }
        if connected {
            if let lastCallAt {
                return Self.relative(lastCallAt, now: now)
            }
            return "mcp.connected".localized()
        }
        return "mcp.disconnected".localized()
    }

    private static func relative(_ date: Date, now: Date) -> String {
        let unit = McpElapsedUnit.from(seconds: Int(now.timeIntervalSince(date)))
        return String(format: unit.localizationKey.localized(), unit.count)
    }
}
