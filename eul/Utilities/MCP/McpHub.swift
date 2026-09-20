import Foundation

actor McpHub {
    static let shared = McpHub()

    private let aggregator: McpAggregator
    private let http: McpLoopbackHTTP
    private var catalog = McpCatalog.empty
    private var listening = false
    private var lastError: String?
    private var running = false
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
            servers: await aggregator.snapshot(catalog: catalog)
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
        await aggregator.setOnActivity {
            Task { await McpHub.shared.notifySoon() }
        }
        catalog = McpCatalogStore.load()
        if catalog.servers.isEmpty {
            try? McpCatalogStore.save(catalog)
        }
        watchCatalog()
        await applyCatalog(restartHTTP: true)
    }

    func stop() async {
        running = false
        notifyTask?.cancel()
        await aggregator.setOnActivity(nil)
        catalogSource?.cancel()
        catalogSource = nil
        catalogFileHandle?.closeFile()
        catalogFileHandle = nil
        await http.stop()
        await aggregator.replaceClients([])
        connectedEntries.removeAll()
        crashRelaunchUsed.removeAll()
        connecting.removeAll()
        listening = false
        lastError = nil
        notify()
    }

    func setServerEnabled(id: String, enabled: Bool) async {
        catalog.setEnabled(id: id, enabled: enabled)
        await persistCatalog()
    }

    private func persistCatalog() async {
        ignoreCatalogWrite = true
        try? McpCatalogStore.save(catalog)
        ignoreCatalogWrite = false
        await applyCatalog(restartHTTP: false)
    }

    private func applyCatalog(restartHTTP: Bool) async {
        let enabled = catalog.servers.filter(\.enabled)
        let enabledIds = Set(enabled.map(\.id))
        var changed = false

        let existing = await aggregator.allClients()
        let dropped = existing.filter { !enabledIds.contains($0.id) }
        if !dropped.isEmpty {
            changed = true
            await aggregator.replaceClients(existing.filter { enabledIds.contains($0.id) })
            for gone in dropped {
                connectedEntries[gone.id] = nil
                crashRelaunchUsed.remove(gone.id)
            }
        }

        for entry in enabled {
            if connecting.contains(entry.id) {
                continue
            }
            let current = await aggregator.client(id: entry.id)
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
            }
            if let client = await connectWithRetry(entry) {
                await aggregator.putClient(client)
                connectedEntries[entry.id] = entry
                crashRelaunchUsed.remove(entry.id)
                connecting.remove(entry.id)
                await aggregator.clearFailed(id: entry.id)
                if let process = client.process, !process.isRunning {
                    await handleUpstreamExit(id: entry.id, process: process)
                }
            } else {
                connectedEntries[entry.id] = nil
                crashRelaunchUsed.remove(entry.id)
                connecting.remove(entry.id)
            }
        }

        if restartHTTP || !listening {
            do {
                try await http.start(port: catalog.listenPort)
                listening = true
                lastError = nil
            } catch {
                listening = false
                lastError = error.localizedDescription
                await aggregator.replaceClients([])
                connectedEntries.removeAll()
                crashRelaunchUsed.removeAll()
                notify()
                return
            }
        }

        if changed {
            await http.notifyToolsListChanged()
        }
        notify()
    }

    private func connectWithRetry(_ entry: McpServerEntry) async -> McpUpstreamClient? {
        do {
            return try await connectEntry(entry)
        } catch {
            do {
                return try await connectEntry(entry)
            } catch {
                await aggregator.markFailed(id: entry.id, message: error.localizedDescription)
                return nil
            }
        }
    }

    private func connectEntry(_ entry: McpServerEntry) async throws -> McpUpstreamClient {
        let id = entry.id
        return try await McpUpstream.connect(entry, onProcessExit: { process in
            Task { await McpHub.shared.handleUpstreamExit(id: id, process: process) }
        })
    }

    private func handleUpstreamExit(id: String, process: Process) async {
        guard running else {
            return
        }
        let current = await aggregator.client(id: id)
        guard current?.process === process else {
            return
        }
        if process.isRunning {
            return
        }
        if connecting.contains(id) {
            return
        }

        connecting.insert(id)
        defer { connecting.remove(id) }
        await aggregator.removeClient(id: id)

        guard let entry = catalog.servers.first(where: { $0.id == id && $0.enabled }) else {
            await failUpstream(id: id, message: "process exited")
            return
        }
        if crashRelaunchUsed.contains(id) {
            await failUpstream(id: id, message: "process exited")
            return
        }
        crashRelaunchUsed.insert(id)

        do {
            let client = try await connectEntry(entry)
            await aggregator.putClient(client)
            connectedEntries[id] = entry
            await aggregator.clearFailed(id: id)
            await http.notifyToolsListChanged()
            notify()
        } catch {
            await failUpstream(id: id, message: error.localizedDescription)
        }
    }

    private func failUpstream(id: String, message: String) async {
        connectedEntries[id] = nil
        await aggregator.markFailed(id: id, message: message)
        await http.notifyToolsListChanged()
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
        source.setEventHandler { [weak self] in
            Task { await self?.catalogDidChange() }
        }
        source.resume()
        catalogSource = source
    }

    private func catalogDidChange() async {
        if ignoreCatalogWrite {
            return
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        catalog = McpCatalogStore.load()
        await applyCatalog(restartHTTP: false)
    }

    private func notifySoon() {
        notifyTask?.cancel()
        notifyTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else {
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
