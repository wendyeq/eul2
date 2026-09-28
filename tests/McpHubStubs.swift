import Foundation

// Only the catalog's filesystem is real. No sockets, subprocesses or user paths.
enum McpPaths {
    static let defaultPort = 19840
    static let catalogURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MCP_HUB_TEST_DIR"]!).appendingPathComponent("catalog.json")
    static func writeAtomic(_ data: Data, to url: URL, posixPermissions _: Int) throws {
        try data.write(to: url, options: .atomic)
    }
}

extension Notification.Name {
    static let mcpHubDidChange = Notification.Name("McpHubFixtureChanged")
}

struct McpServerStatus {
    var id: String
    var connected: Bool
    var connecting: Bool
}

struct McpUpstreamClient {
    var id: String
    var process: Process? = nil
}

actor Fixture {
    static let shared = Fixture()
    var httpStarts = 0
    var httpLive = false
    var connects: [String] = []
    var failures = 0
    var toolsNotifications = 0
    var shutdowns = 0
    var holdHTTP = false
    var holdConnect = false
    var failConnect = false
    var httpWaiter: CheckedContinuation<Void, Never>?
    var connectWaiter: CheckedContinuation<Void, Never>?
    func configure(http: Bool = false, connect: Bool = false, fail: Bool = false) {
        holdHTTP = http; holdConnect = connect; failConnect = fail
    }

    func startHTTP() async {
        httpStarts += 1
        if holdHTTP { await withCheckedContinuation { httpWaiter = $0 } }
        httpLive = true
    }

    func releaseHTTP() { holdHTTP = false; httpWaiter?.resume(); httpWaiter = nil }
    func releaseConnect() { holdConnect = false; connectWaiter?.resume(); connectWaiter = nil }
    func stopHTTP() { httpLive = false }
    func connect(_ id: String) async throws -> McpUpstreamClient {
        connects.append(id)
        if holdConnect { await withCheckedContinuation { connectWaiter = $0 } }
        if failConnect { throw NSError(domain: "fixture", code: 1) }
        return McpUpstreamClient(id: id)
    }

    func shutdownEntered() { shutdowns += 1 }
    func markFailed() { failures += 1 }
    func toolsChanged() { toolsNotifications += 1 }
    func counts() -> (Int, Int, Int, Int) { (httpStarts, connects.count, failures, toolsNotifications) }
}

actor McpAggregator {
    var clients: [String: McpUpstreamClient] = [:]
    func setOnActivity(_ handler: (@Sendable () -> Void)?) async {
        if handler == nil { await Fixture.shared.shutdownEntered() }
    }

    func allClients() -> [McpUpstreamClient] { Array(clients.values) }
    func replaceClients(_ next: [McpUpstreamClient]) { clients = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0) }) }
    func client(id: String) -> McpUpstreamClient? { clients[id] }
    func putClient(_ client: McpUpstreamClient) { clients[client.id] = client }
    func removeClient(id: String) { clients[id] = nil }
    func clearFailed(id _: String) {}
    func markFailed(id _: String, message _: String) async { await Fixture.shared.markFailed() }
    func snapshot(catalog: McpCatalog, connecting: Set<String>) -> [McpServerStatus] {
        catalog.servers.map { McpServerStatus(id: $0.id, connected: clients[$0.id] != nil, connecting: connecting.contains($0.id)) }
    }
}

actor McpLoopbackHTTP {
    init(aggregator _: McpAggregator) {}
    func start(port _: Int) async throws { await Fixture.shared.startHTTP() }
    func stop() async { await Fixture.shared.stopHTTP() }
    func notifyToolsListChanged() async { await Fixture.shared.toolsChanged() }
}

enum McpUpstream {
    struct TimeoutError: Error {}
    static func connect(_ entry: McpServerEntry, onProcessExit _: @escaping @Sendable (Process) -> Void) async throws -> McpUpstreamClient {
        try await Fixture.shared.connect(entry.id)
    }
}
