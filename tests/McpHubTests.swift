import Foundation

@main enum McpHubTests {
    static func check(_ value: Bool, _ message: String) {
        if !value { print("FAIL: \(message)"); exit(1) }
    }

    static func eventually(_ message: String, _ condition: () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        check(false, "timed out: \(message)")
    }

    static func settle() async { try? await Task.sleep(nanoseconds: 650_000_000) }
    static func main() async throws {
        let hub = McpHub()
        try McpCatalogStore.save(McpCatalog(version: 1, port: 19840, servers: [
            McpServerEntry(id: "a"), McpServerEntry(id: "b", enabled: false),
        ]))
        await hub.start()
        await eventually("initial connection") { await hub.snapshot().servers.first?.connected == true }
        await hub.stop()
        let before = await Fixture.shared.counts()
        await hub.moveServer(from: 0, to: 1)
        await hub.setServerEnabled(id: "a", enabled: false)
        await hub.setServerEnabled(id: "b", enabled: true)
        await settle()
        let after = await Fixture.shared.counts()
        check(after.0 == before.0, "stopped edits must not start HTTP")
        check(after.1 == before.1, "stopped edits must not start upstreams")
        check(await hub.snapshot().listening == false, "stopped snapshot stays stopped")
        let saved = McpCatalogStore.load()
        check(saved.servers.map(\.id) == ["b", "a"], "saved ordering")
        check(saved.servers.map(\.enabled) == [true, false], "saved switches")
        await hub.start()
        await eventually("restart saved configuration") { await hub.snapshot().servers.first?.connected == true }
        check(await hub.currentCatalog() == saved, "restart loads saved catalog")
        check(await Fixture.shared.connects.last == "b", "restart connects enabled server")
        await hub.stop()
        print("PASS: stopped edits persist without HTTP/upstream restart; explicit start uses saved configuration")

        // Hold readiness exactly where the real HTTP actor suspends before
        // publishing its listener. A new start must wait for shutdown to drain it.
        let httpHub = McpHub()
        await Fixture.shared.configure(http: true)
        let httpBefore = await Fixture.shared.counts()
        let firstStart = Task { await httpHub.start() }
        await eventually("HTTP readiness suspended") { await Fixture.shared.httpWaiter != nil }
        let shutdowns = await Fixture.shared.shutdowns
        let stop = Task { await httpHub.stop() }
        await eventually("stop entered") { await Fixture.shared.shutdowns == shutdowns + 1 }
        let stoppedGeneration = await httpHub.fixtureGeneration()
        let restart = Task { await httpHub.start() }
        await eventually("restart awaiting shutdown") { await httpHub.fixtureGeneration() == stoppedGeneration + 1 }
        // Edits while the restart request waits must stay persistence-only.
        await httpHub.setServerEnabled(id: "b", enabled: false)
        await httpHub.setServerEnabled(id: "b", enabled: true)
        check(await Fixture.shared.counts().0 == httpBefore.0 + 1, "restart waits for pending HTTP startup")
        await Fixture.shared.releaseHTTP()
        await firstStart.value
        await stop.value
        await restart.value
        await eventually("new generation connects") { await httpHub.snapshot().servers.first?.connected == true }
        check(await Fixture.shared.counts().0 == httpBefore.0 + 2, "exactly one new listener after drain")
        check(await Fixture.shared.httpLive, "new listener remains live")
        await httpHub.stop()
        check(await Fixture.shared.httpLive == false, "listener stopped after restart")
        print("PASS: stop during HTTP readiness drains startup; rapid restart is preserved")

        let retryHub = McpHub()
        await Fixture.shared.configure(connect: true, fail: true)
        let retryBefore = await Fixture.shared.counts()
        await retryHub.start()
        await eventually("upstream suspended") { await Fixture.shared.connectWaiter != nil }
        await retryHub.stop()
        await Fixture.shared.releaseConnect()
        await settle()
        let retryAfter = await Fixture.shared.counts()
        check(retryAfter.1 == retryBefore.1 + 1, "old connection failure must not retry")
        check(retryAfter.2 == retryBefore.2, "old connection failure must not mark failed")
        check(await retryHub.snapshot().servers.allSatisfy { !$0.connected && !$0.connecting }, "old failure leaves hub stopped")
        print("PASS: in-flight upstream failure does not retry or publish failure after stop")

        let lateHub = McpHub()
        await Fixture.shared.configure(connect: true)
        await lateHub.start()
        await eventually("late success suspended") { await Fixture.shared.connectWaiter != nil }
        await lateHub.stop()
        let lateBefore = await Fixture.shared.counts()
        await Fixture.shared.releaseConnect()
        await settle()
        check(await lateHub.snapshot().servers.allSatisfy { !$0.connected && !$0.connecting }, "late successful connection is discarded")
        check(await Fixture.shared.counts().3 == lateBefore.3, "late success sends no tools notification")
        print("PASS: in-flight successful upstream is not installed after stop")

        let eventHub = McpHub()
        await Fixture.shared.configure()
        await eventHub.start()
        await eventually("catalog event hub connected") { await eventHub.snapshot().servers.first?.connected == true }
        let eventGeneration = await eventHub.fixtureGeneration()
        let original = await eventHub.currentCatalog()
        var replacement = original
        replacement.setEnabled(id: "a", enabled: true)
        let eventBefore = await Fixture.shared.counts()
        await eventHub.fixtureCatalogEventThenStop(replacement: replacement)
        check(await eventHub.currentCatalog() == original, "debounced event does not reload catalog after stop")
        check(await Fixture.shared.counts().0 == eventBefore.0, "debounced event does not relisten after stop")
        check(await Fixture.shared.counts().1 == eventBefore.1, "debounced event does not connect after stop")
        await eventHub.start()
        await eventually("replacement catalog connects") { await eventHub.snapshot().servers.allSatisfy(\.connected) }
        let restartedCounts = await Fixture.shared.counts()
        var stale = replacement
        stale.setEnabled(id: "a", enabled: false)
        try await eventHub.fixtureOldCatalogEvent(generation: eventGeneration, diskCatalog: stale)
        check(await Fixture.shared.counts().0 == restartedCounts.0, "old watcher event is rejected after restart")
        check(await eventHub.currentCatalog() == replacement, "stale watcher does not replace the restarted catalog")
        await eventHub.stop()
        print("PASS: stop during catalog debounce rejects reload/start; stale watcher callback rejected after restart")
    }
}
