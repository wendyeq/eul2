import SwiftUI

extension Preference {
    struct McpView: View {
        @EnvironmentObject var preference: PreferenceStore
        @EnvironmentObject var mcpStore: McpStore

        var body: some View {
            VStack(alignment: .leading, spacing: PreferenceChrome.formRowSpacing) {
                PreferenceInsetFormGroup {
                    PreferenceFormSwitchRow(
                        title: "mcp.hub_enabled".localized(),
                        isOn: $preference.mcpHubEnabled,
                        showsDivider: false
                    )
                }
                HStack(spacing: 8) {
                    Button("mcp.connect_agents".localized()) {
                        mcpStore.connectAgents()
                    }
                    Button("mcp.open_catalog".localized()) {
                        mcpStore.openCatalog()
                    }
                }
                .padding(.top, 4)
                if let message = mcpStore.statusMessage {
                    Text(message)
                        .secondaryDisplayText()
                }
                Text(statusLine)
                    .secondaryDisplayText()
                if !mcpStore.servers.isEmpty {
                    PreferenceInsetFormGroup {
                        ForEach(Array(mcpStore.servers.enumerated()), id: \.element.id) { index, server in
                            PreferenceFormSwitchRow(
                                title: server.id,
                                isOn: Binding(
                                    get: { server.enabled },
                                    set: { mcpStore.setServerEnabled(id: server.id, enabled: $0) }
                                ),
                                showsDivider: index < mcpStore.servers.count - 1
                            )
                        }
                    }
                }
            }
        }

        private var statusLine: String {
            if let error = mcpStore.lastError, !error.isEmpty {
                return "mcp.failed".localized() + " · \(error)"
            }
            if mcpStore.listening {
                return "mcp.listening".localized() + " · 127.0.0.1:\(mcpStore.port)"
            }
            return "mcp.stopped".localized()
        }
    }
}
