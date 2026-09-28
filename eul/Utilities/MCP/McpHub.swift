import Foundation

actor McpHub {
    static let shared = McpHub()

    private let aggregator: McpAggregator
    private let http: McpLoopbackHTTP
    private var catalog = McpCatalog.empty
    private var listening = false
    private var lastError: String?
    private var running = false
    private var generation = 0
    private var httpStartTask: Task<Void, Error>?
    private var shutdownTask: Task<Void, Never>?
    private var connectedEntries: [String: McpServerEntry] = [:]
    private var crashRelaunchUsed: Set<String> = []
    private var connecting: Set<String> = []
    private var catalogSource: DispatchSourceFileSystemObject?
    private var catalogFileHandle: FileHandle?
    private var ignoreCatalogWrite = false
    private var notifyTask: Task<Void, Never>?

    init() {
        let aggregator = McpAggregator()
        self.aggregator = aggregator
        http = McpLoopbackHTTP(aggregator: aggregator)
    }

    func snapshot() async -> McpHubSnapshot {
        McpHubSnapshot(
            listening: listening,
            lastError: lastError,
            port: catalog.listenPort,
            servers: await aggregator.snapshot(catalog: catalog, connecting: connecting)
        )
    }

    func currentCatalog() -> McpCatalog {
        catalog
    }

    func start() async {
        guard !running else {
            return
        }
        running = true
        generation += 1
        let gen = generation
        await shutdownTask?.value
        guard running, generation == gen else { return }
        shutdownTask = nil
        httpStartTask = nil
        await aggregator.setOnActivity { [weak self] in
            Task { await self?.notifySoon(generation: gen) }
        }
        guard running, generation == gen else { return }
        catalog = McpCatalogStore.load()
        if catalog.servers.isEmpty {
            try? McpCatalogStore.save(catalog)
        }
        watchCatalog()
        await applyCatalog(restartHTTP: true)
    }

    func stop() async {
        generation += 1
        running = false
        let gen = generation
        notifyTask?.cancel()
        catalogSource?.cancel()
        catalogSource = nil
        catalogFileHandle?.closeFile()
        catalogFileHandle = nil
        connectedEntries.removeAll()
        crashRelaunchUsed.removeAll()
        connecting.removeAll()
        listening = false
        lastError = nil
        // HTTP.start publishes its listener after awaiting readiness. Drain it
        // before stopping, and make a subsequent start wait for this cleanup.
        let pendingStart = httpStartTask
        let previousShutdown = shutdownTask
        let shutdown = Task { [aggregator, http] in
            await previousShutdown?.value
            await aggregator.setOnActivity(nil)
            _ = try? await pendingStart?.value
            await http.stop()
            await aggregator.replaceClients([])
        }
        shutdownTask = shutdown
        await shutdown.value
        guard generation == gen else { return }
        httpStartTask = nil
        shutdownTask = nil
        notify()
    }

    func setServerEnabled(id: String, enabled: Bool) async {
        catalog.setEnabled(id: id, enabled: enabled)
        await persistCatalog()
    }

    func moveServer(from offset: Int, to destination: Int) async {
        catalog.moveServer(from: offset, to: destination)
        await persistCatalog()
    }

    private func persistCatalog() async {
        ignoreCatalogWrite = true
        try? McpCatalogStore.save(catalog)
        ignoreCatalogWrite = false
        await applyCatalog(restartHTTP: false)
    }

    private func applyCatalog(restartHTTP: Bool) async {
        guard running else {
            notify()
            return
        }
        // A requested restart can be waiting for the previous shutdown. Edits
        // still save, but only start() may apply them once cleanup has drained.
        guard shutdownTask == nil else {
            notify()
            return
        }
        let gen = generation
        let enabled = catalog.servers.filter(\.enabled)
        let enabledIds = Set(enabled.map(\.id))
        var changed = false

        let existing = await aggregator.allClients()
        guard running, generation == gen else { return }
        let dropped = existing.filter { !enabledIds.contains($0.id) }
        if !dropped.isEmpty {
            changed = true
            await aggregator.replaceClients(existing.filter { enabledIds.contains($0.id) })
            guard running, generation == gen else { return }
            for gone in dropped {
                connectedEntries[gone.id] = nil
                crashRelaunchUsed.remove(gone.id)
            }
        }

        if restartHTTP || !listening {
            do {
                if httpStartTask == nil {
                    let port = catalog.listenPort
                    httpStartTask = Task { [http] in try await http.start(port: port) }
                }
                try await httpStartTask?.value
                guard running, generation == gen else { return }
                httpStartTask = nil
                listening = true
                lastError = nil
            } catch {
                guard running, generation == gen else { return }
                httpStartTask = nil
                listening = false
                lastError = error.localizedDescription
                await aggregator.replaceClients([])
                guard running, generation == gen else { return }
                connectedEntries.removeAll()
                crashRelaunchUsed.removeAll()
                connecting.removeAll()
                notify()
                return
            }
            notify()
        }

        for entry in enabled {
            if connecting.contains(entry.id) {
                continue
            }
            let current = await aggregator.client(id: entry.id)
            guard running, generation == gen else { return }
            let keepable: Bool = {
                guard let current, connectedEntries[entry.id] == entry else {
                    return false
                }
                if let process = current.process {
                    return process.isRunning
                }
                return true
            }()
            if keepable {
                continue
            }
            changed = true
            connecting.insert(entry.id)
            if current != nil {
                await aggregator.removeClient(id: entry.id)
                guard running, generation == gen else { return }
            }
            Task {
                await self.finishConnect(entry: entry, generation: gen)
            }
        }

        if changed {
            await http.notifyToolsListChanged()
            guard running, generation == gen else { return }
        }
        notify()
    }

    private func finishConnect(entry: McpServerEntry, generation gen: Int) async {
        guard running, generation == gen else { return }
        let client = await connectWithRetry(entry, generation: gen)
        defer {
            if generation == gen { connecting.remove(entry.id) }
        }
        guard running, generation == gen,
              catalog.servers.contains(entry), entry.enabled
        else {
            discard(client)
            return
        }
        if let client {
            await aggregator.putClient(client)
            guard running, generation == gen else { return }
            connectedEntries[entry.id] = entry
            crashRelaunchUsed.remove(entry.id)
            await aggregator.clearFailed(id: entry.id)
            guard running, generation == gen else { return }
            if let process = client.process, !process.isRunning {
                await handleUpstreamExit(id: entry.id, process: process, generation: gen)
                guard running, generation == gen else { return }
            }
            await http.notifyToolsListChanged()
            guard running, generation == gen else { return }
        } else {
            connectedEntries[entry.id] = nil
            crashRelaunchUsed.remove(entry.id)
        }
        notify()
    }

    private func discard(_ client: McpUpstreamClient?) {
        guard let process = client?.process else {
            return
        }
        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
        }
    }

    private func connectWithRetry(_ entry: McpServerEntry, generation gen: Int) async -> McpUpstreamClient? {
        do {
            return try await connectEntry(entry, generation: gen)
        } catch is McpUpstream.TimeoutError {
            guard running, generation == gen else { return nil }
            await aggregator.markFailed(id: entry.id, message: "connect timeout")
            return nil
        } catch {
            guard running, generation == gen else { return nil }
            do {
                return try await connectEntry(entry, generation: gen)
            } catch {
                guard running, generation == gen else { return nil }
                await aggregator.markFailed(id: entry.id, message: error.localizedDescription)
                return nil
            }
        }
    }

    private func connectEntry(_ entry: McpServerEntry, generation gen: Int) async throws -> McpUpstreamClient {
        guard running, generation == gen else { throw CancellationError() }
        let id = entry.id
        return try await McpUpstream.connect(entry, onProcessExit: { [weak self] process in
            Task { await self?.handleUpstreamExit(id: id, process: process, generation: gen) }
        })
    }

    private func handleUpstreamExit(id: String, process: Process, generation gen: Int) async {
        guard running, generation == gen else {
            return
        }
        let current = await aggregator.client(id: id)
        guard running, generation == gen, current?.process === process else {
            return
        }
        if process.isRunning {
            return
        }
        if connecting.contains(id) {
            return
        }

        connecting.insert(id)
        defer {
            if generation == gen { connecting.remove(id) }
        }
        await aggregator.removeClient(id: id)
        guard running, generation == gen else { return }

        guard let entry = catalog.servers.first(where: { $0.id == id && $0.enabled }) else {
            await failUpstream(id: id, message: "process exited", generation: gen)
            return
        }
        if crashRelaunchUsed.contains(id) {
            await failUpstream(id: id, message: "process exited", generation: gen)
            return
        }
        crashRelaunchUsed.insert(id)

        do {
            let client = try await connectEntry(entry, generation: gen)
            guard running, generation == gen,
                  catalog.servers.contains(entry), entry.enabled
            else {
                discard(client)
                return
            }
            await aggregator.putClient(client)
            guard running, generation == gen else { return }
            connectedEntries[id] = entry
            await aggregator.clearFailed(id: id)
            guard running, generation == gen else { return }
            await http.notifyToolsListChanged()
            guard running, generation == gen else { return }
            notify()
        } catch {
            await failUpstream(id: id, message: error.localizedDescription, generation: gen)
        }
    }

    private func failUpstream(id: String, message: String, generation gen: Int) async {
        guard running, generation == gen else { return }
        connectedEntries[id] = nil
        await aggregator.markFailed(id: id, message: message)
        guard running, generation == gen else { return }
        await http.notifyToolsListChanged()
        guard running, generation == gen else { return }
        notify()
    }

    private func watchCatalog() {
        catalogSource?.cancel()
        catalogFileHandle?.closeFile()
        let path = McpPaths.catalogURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            return
        }
        let handle = FileHandle(forReadingAtPath: path)
        catalogFileHandle = handle
        guard let descriptor = handle?.fileDescriptor else {
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global()
        )
        let gen = generation
        source.setEventHandler { [weak self] in
            Task { await self?.catalogDidChange(generation: gen) }
        }
        source.resume()
        catalogSource = source
    }

    private func catalogDidChange(generation gen: Int) async {
        guard running, generation == gen, !ignoreCatalogWrite else {
            return
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard running, generation == gen, !Task.isCancelled else { return }
        catalog = McpCatalogStore.load()
        await applyCatalog(restartHTTP: false)
    }

    private func notifySoon(generation gen: Int) {
        guard running, generation == gen else { return }
        notifyTask?.cancel()
        notifyTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard running, generation == gen, !Task.isCancelled else {
                return
            }
            notify()
        }
    }

    private func notify() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .mcpHubDidChange, object: nil)
        }
    }
}

struct McpHubSnapshot {
    var listening: Bool
    var lastError: String?
    var port: Int
    var servers: [McpServerStatus]
}
