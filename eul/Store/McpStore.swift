import AppKit
import Combine
import Foundation

class McpStore: ObservableObject {
    @Published var listening = false
    @Published var lastError: String?
    @Published var port = McpPaths.defaultPort
    @Published var servers: [McpServerStatus] = []
    @Published var statusMessage: String?

    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: .mcpHubDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
        SharedStore.preference.$mcpHubEnabled
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.applyEnabled(enabled)
            }
            .store(in: &cancellables)
        refresh()
    }

    func refresh() {
        Task {
            let snapshot = await McpHub.shared.snapshot()
            await MainActor.run {
                listening = snapshot.listening
                lastError = snapshot.lastError
                port = snapshot.port
                servers = snapshot.servers
            }
        }
    }

    func applyEnabled(_ enabled: Bool) {
        Task {
            if enabled {
                await McpHub.shared.start()
            } else {
                await McpHub.shared.stop()
            }
            refresh()
        }
    }

    func setServerEnabled(id: String, enabled: Bool) {
        Task {
            await McpHub.shared.setServerEnabled(id: id, enabled: enabled)
            refresh()
        }
    }

    func moveServer(from offset: Int, to destination: Int) {
        Task {
            await McpHub.shared.moveServer(from: offset, to: destination)
            refresh()
        }
    }

    func openCatalog() {
        Task {
            var catalog = await McpHub.shared.currentCatalog()
            if catalog.servers.isEmpty {
                catalog = McpCatalogStore.load()
            }
            try? McpCatalogStore.save(catalog)
            await MainActor.run {
                NSWorkspace.shared.open(McpPaths.catalogURL)
            }
        }
    }

    func connectAgents() {
        let executable = Bundle.main.executableURL?.path
            ?? "/Applications/eul2.app/Contents/MacOS/eul"
        let result = McpAgentWriter.connectAgents(executable: executable, port: port)
        if result.failed.isEmpty {
            statusMessage = "mcp.connect_ok".localized()
        } else {
            statusMessage = "mcp.connect_failed".localized() + " " + result.failed.joined(separator: ", ")
        }
    }
}
