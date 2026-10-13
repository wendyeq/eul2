import Foundation

@main enum McpHubTests {
    static func check(_ value: Bool, _ message: String) {
        if !value { print("FAIL: \(message)"); exit(1) }
    }

    static func eventually(_ message: String, attempts: Int = 200, _ condition: () async -> Bool) async {
        for _ in 0..<attempts {
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

        let deadHub = McpHub()
        await Fixture.shared.configure()
        await Fixture.shared.armDeadHandshake("a")
        try McpCatalogStore.save(McpCatalog(version: 1, port: 19840, servers: [
            McpServerEntry(id: "a", command: "seed"),
        ]))
        let deadBefore = await Fixture.shared.counts()
        await deadHub.start()
        await eventually("dead handshake relaunches") { await deadHub.snapshot().servers.first?.connected == true }
        let deadAfter = await Fixture.shared.counts()
        check(deadAfter.1 == deadBefore.1 + 2, "process already exited after handshake is relaunched once")
        check(deadAfter.2 == deadBefore.2, "successful relaunch does not stay failed")
        check(await deadHub.snapshot().servers.first?.connecting == false, "relaunched server is not stuck connecting")
        await deadHub.stop()
        print("PASS: handshake that exits immediately is removed and relaunched")

        let editHub = McpHub()
        await Fixture.shared.configure(connect: true)
        try McpCatalogStore.save(McpCatalog(version: 1, port: 19840, servers: [
            McpServerEntry(id: "a", command: "old"),
        ]))
        let editBefore = await Fixture.shared.counts()
        await editHub.start()
        await eventually("edit suspended") { await Fixture.shared.connectWaiter != nil }
        await editHub.fixtureReplaceCommand(id: "a", command: "new")
        await Fixture.shared.releaseConnect()
        await eventually("edited server reconnects") { await editHub.snapshot().servers.first?.connected == true }
        check(await Fixture.shared.commands.last == "new", "reconnect uses the edited command")
        check(await Fixture.shared.counts().1 >= editBefore.1 + 2, "edited command is not dropped after the in-flight connect")
        await editHub.stop()
        print("PASS: catalog edit during connect is applied after the handshake")

        let watchHub = McpHub()
        await Fixture.shared.configure()
        try McpCatalogStore.save(McpCatalog(version: 1, port: 19840, servers: [
            McpServerEntry(id: "a", command: "seed"), McpServerEntry(id: "b", command: "other"),
        ]))
        await watchHub.start()
        await eventually("watch hub connected") { await watchHub.snapshot().servers.allSatisfy(\.connected) }
        var disabled = McpCatalogStore.load()
        disabled.setEnabled(id: "b", enabled: false)
        try McpCatalogStore.save(disabled)
        await eventually("first atomic replace", attempts: 800) {
            let servers = await watchHub.snapshot().servers
            return servers.first { $0.id == "b" }?.connected == false && servers.first { $0.id == "a" }?.connected == true
        }
        var rewritten = McpCatalogStore.load()
        if let index = rewritten.servers.firstIndex(where: { $0.id == "a" }) {
            rewritten.servers[index].command = "rewritten"
        }
        let marked = await Fixture.shared.commands.count
        try McpCatalogStore.save(rewritten)
        await eventually("second atomic replace reconnects", attempts: 800) {
            let commands = await Fixture.shared.commands
            return commands.count > marked && commands.last == "rewritten"
        }
        check(await watchHub.currentCatalog().servers.first { $0.id == "a" }?.command == "rewritten", "second replace reloaded the catalog")
        await watchHub.stop()
        print("PASS: atomic catalog replacement rearms the watcher")

        let installHub = McpHub()
        await Fixture.shared.configure()
        try McpCatalogStore.save(McpCatalog(version: 1, port: 19840, servers: [
            McpServerEntry(id: "a", command: "keep"),
            McpServerEntry(id: "b", enabled: false, command: "side"),
        ]))
        await Fixture.shared.setOnPut {
            await installHub.fixtureEnable(id: "b")
        }
        let removalsBefore = await Fixture.shared.removals
        await installHub.start()
        await eventually("install published beside the other server") {
            let servers = await installHub.snapshot().servers
            let kept = servers.first { $0.id == "a" }
            let side = servers.first { $0.id == "b" }
            return kept?.connected == true && kept?.connecting == false && side?.connected == true
        }
        check(await Fixture.shared.commands.filter { $0 == "keep" }.count == 1, "same entry is not started twice while its client is being published")
        check(await Fixture.shared.removals == removalsBefore, "publishing install is not terminated by an interleaved catalog apply")
        await installHub.stop()
        print("PASS: catalog apply during client install keeps the same upstream")

        let relaunchHub = McpHub()
        await Fixture.shared.configure(connect: true)
        await Fixture.shared.armDeadHandshake("a")
        try McpCatalogStore.save(McpCatalog(version: 1, port: 19840, servers: [
            McpServerEntry(id: "a", command: "old"),
        ]))
        let relaunchBefore = await Fixture.shared.connects.count
        await relaunchHub.start()
        await eventually("dead relaunch held") {
            let count = await Fixture.shared.connects.count
            let waiting = await Fixture.shared.connectWaiter != nil
            return count == relaunchBefore + 1 && waiting
        }
        await Fixture.shared.resumeConnect()
        await eventually("replacement connect held") {
            let count = await Fixture.shared.connects.count
            let waiting = await Fixture.shared.connectWaiter != nil
            return count == relaunchBefore + 2 && waiting
        }
        await relaunchHub.fixtureReplaceCommand(id: "a", command: "new")
        await Fixture.shared.resumeConnect()
        await eventually("edited relaunch held") {
            let command = await Fixture.shared.commands.last
            let waiting = await Fixture.shared.connectWaiter != nil
            return command == "new" && waiting
        }
        let heldConnects = await Fixture.shared.connects.count
        await relaunchHub.fixtureApplyCatalog()
        check(await Fixture.shared.connects.count == heldConnects, "stale relaunch cleanup must not drop the replacement attempt")
        check(await relaunchHub.snapshot().servers.first?.connecting == true, "replacement attempt stays in flight")
        await Fixture.shared.releaseConnect()
        await eventually("edited relaunch connected") {
            let server = await relaunchHub.snapshot().servers.first
            return server?.connected == true && server?.connecting == false
        }
        check(await Fixture.shared.commands.last == "new", "crash relaunch uses the edited command")
        await relaunchHub.stop()
        print("PASS: config edited during crash relaunch is connected, and the old attempt cannot clear it")

        let cancelHub = McpHub()
        await Fixture.shared.configure(http: true, cancelHTTP: true)
        try McpCatalogStore.save(McpCatalog(version: 1, port: 19840, servers: [
            McpServerEntry(id: "a", command: "keep"),
        ]))
        let cancelStart = Task { await cancelHub.start() }
        await eventually("readiness held") { await Fixture.shared.httpWaiter != nil }
        await cancelHub.stop()
        await cancelStart.value
        check(await Fixture.shared.httpLive == false, "stop cancels readiness without releaseHTTP")
        check(await cancelHub.snapshot().listening == false, "cancelled readiness stays stopped")
        print("PASS: stop unblocks a pending HTTP start without an external resume")

        let earlyHub = McpHub()
        await Fixture.shared.configure(cancelHTTP: true, beforePublish: true)
        let earlyStart = Task { await earlyHub.start() }
        await eventually("publish held") { await Fixture.shared.publishWaiter != nil }
        let earlyStop = Task { await earlyHub.stop() }
        await eventually("stop arrived before publish") { await Fixture.shared.stopBeforePublish }
        await Fixture.shared.releasePublish()
        await earlyStop.value
        await earlyStart.value
        check(await earlyHub.snapshot().listening == false, "stop before listener publish finishes shutdown")
        check(await Fixture.shared.httpLive == false, "listener is not published after a pre-publish stop")
        print("PASS: stop before listener publish unblocks startup")
    }
}
