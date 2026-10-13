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
    var commands: [String?] = []
    var deadIds: Set<String> = []
    var failures = 0
    var toolsNotifications = 0
    var shutdowns = 0
    var removals = 0
    var holdHTTP = false
    var holdConnect = false
    var failConnect = false
    var cancelHTTPOnStop = false
    var holdBeforePublish = false
    var stopBeforePublish = false
    var listenerPublished = false
    var httpWaiter: CheckedContinuation<Void, Error>?
    var publishWaiter: CheckedContinuation<Void, Never>?
    var connectWaiter: CheckedContinuation<Void, Never>?
    var onPut: (@Sendable () async -> Void)?
    func configure(http: Bool = false, connect: Bool = false, fail: Bool = false, cancelHTTP: Bool = false, beforePublish: Bool = false) {
        holdHTTP = http
        holdConnect = connect
        failConnect = fail
        cancelHTTPOnStop = cancelHTTP
        holdBeforePublish = beforePublish
        stopBeforePublish = false
        listenerPublished = false
        onPut = nil
        deadIds.removeAll()
    }

    func armDeadHandshake(_ id: String) { deadIds.insert(id) }

    func startHTTP() async throws {
        httpStarts += 1
        if holdBeforePublish {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                publishWaiter = continuation
            }
        }
        if stopBeforePublish { throw CancellationError() }
        listenerPublished = true
        if holdHTTP {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                httpWaiter = continuation
            }
        }
        httpLive = true
    }

    func releaseHTTP() { holdHTTP = false; httpWaiter?.resume(); httpWaiter = nil }
    func releasePublish() { holdBeforePublish = false; publishWaiter?.resume(); publishWaiter = nil }
    func releaseConnect() { holdConnect = false; connectWaiter?.resume(); connectWaiter = nil }
    func resumeConnect() { connectWaiter?.resume(); connectWaiter = nil }
    func stopHTTP() {
        httpLive = false
        guard cancelHTTPOnStop else { return }
        if let httpWaiter {
            httpWaiter.resume(throwing: CancellationError())
            self.httpWaiter = nil
            return
        }
        if !listenerPublished { stopBeforePublish = true }
    }

    func setOnPut(_ hook: (@Sendable () async -> Void)?) { onPut = hook }
    func runOnPut() async {
        guard let hook = onPut else { return }
        onPut = nil
        await hook()
    }

    func noteRemoval() { removals += 1 }
    func connect(_ entry: McpServerEntry) async throws -> McpUpstreamClient {
        connects.append(entry.id)
        commands.append(entry.command)
        if holdConnect { await withCheckedContinuation { connectWaiter = $0 } }
        if failConnect { throw NSError(domain: "fixture", code: 1) }
        if deadIds.remove(entry.id) != nil {
            return McpUpstreamClient(id: entry.id, process: Process())
        }
        return McpUpstreamClient(id: entry.id)
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
    func putClient(_ client: McpUpstreamClient) async {
        clients[client.id] = client
        await Fixture.shared.runOnPut()
    }

    func removeClient(id: String) async {
        if clients.removeValue(forKey: id) != nil { await Fixture.shared.noteRemoval() }
    }

    func clearFailed(id _: String) {}
    func markFailed(id _: String, message _: String) async { await Fixture.shared.markFailed() }
    func snapshot(catalog: McpCatalog, connecting: Set<String>) -> [McpServerStatus] {
        catalog.servers.map { McpServerStatus(id: $0.id, connected: clients[$0.id] != nil, connecting: connecting.contains($0.id)) }
    }
}

actor McpLoopbackHTTP {
    init(aggregator _: McpAggregator) {}
    func start(port _: Int) async throws { try await Fixture.shared.startHTTP() }
    func stop() async { await Fixture.shared.stopHTTP() }
    func notifyToolsListChanged() async { await Fixture.shared.toolsChanged() }
}

enum McpUpstream {
    struct TimeoutError: Error {}
    static func connect(_ entry: McpServerEntry, onProcessExit _: @escaping @Sendable (Process) -> Void) async throws -> McpUpstreamClient {
        try await Fixture.shared.connect(entry)
    }
}
