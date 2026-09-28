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
