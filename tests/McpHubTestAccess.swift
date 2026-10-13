// Appended to a temporary copy of McpHub.swift so Swift's file-private access
// permits a deterministic lifecycle trigger. No production logic is rewritten.
extension McpHub {
    func fixtureGeneration() -> Int { generation }

    func fixtureCatalogEventThenStop(replacement: McpCatalog) async {
        // This actor-inheriting task cannot run until catalogDidChange reaches
        // its debounce await. Thus stop occurs inside, not before, that delay.
        let stopTask = Task {
            await self.stop()
            try! McpCatalogStore.save(replacement)
        }
        await catalogDidChange(generation: generation)
        await stopTask.value
    }

    func fixtureEnable(id: String) async {
        catalog.setEnabled(id: id, enabled: true)
        await applyCatalog(restartHTTP: false)
    }

    func fixtureApplyCatalog() async {
        await applyCatalog(restartHTTP: false)
    }

    func fixtureReplaceCommand(id: String, command: String) async {
        guard let index = catalog.servers.firstIndex(where: { $0.id == id }) else { return }
        catalog.servers[index].command = command
        catalogSource?.cancel()
        catalogSource = nil
        catalogFileHandle?.closeFile()
        catalogFileHandle = nil
        ignoreCatalogWrite = true
        try? McpCatalogStore.save(catalog)
        ignoreCatalogWrite = false
        await applyCatalog(restartHTTP: false)
    }

    func fixtureOldCatalogEvent(generation gen: Int, diskCatalog: McpCatalog) async throws {
        // Isolate an already-enqueued old callback from fresh filesystem events.
        catalogSource?.cancel()
        catalogSource = nil
        catalogFileHandle?.closeFile()
        catalogFileHandle = nil
        try McpCatalogStore.save(diskCatalog)
        await catalogDidChange(generation: gen)
    }
}
