import SwiftUI

extension Preference {
    struct McpView: View {
        @EnvironmentObject var preference: PreferenceStore
        @EnvironmentObject var mcpStore: McpStore

        var body: some View {
            VStack(alignment: .leading, spacing: PreferenceChrome.formRowSpacing) {
                PreferenceInsetFormGroup {
                    PreferenceFormSplitRow(showsDivider: false, singleLineLabel: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("mcp.hub_enabled".localized(fallback: "Listen locally"))
                                .preferenceFormLabel()
                            Text("mcp.hub_enabled.detail".localized(fallback: "When on, this Mac listens and starts the servers below. Separate from showing the MCP page."))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } control: {
                        Toggle("", isOn: $preference.mcpHubEnabled)
                            .preferenceFormTrailingSwitch()
                    }
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
                    Text("component.drag_to_reorder".localized())
                        .subsection()
                        .foregroundColor(Color.gray)
                    PreferenceEnabledOrderList(
                        items: mcpStore.servers.map(\.id),
                        coordinateSpace: "McpServersOrdering",
                        isOn: serverEnabledBinding,
                        move: { mcpStore.moveServer(from: $0, to: $1) }
                    ) { id in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(id)
                                .preferenceFormLabel()
                            Text(serverStatus(id))
                                .secondaryDisplayText()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
            }
        }

        private func server(_ id: String) -> McpServerStatus? {
            mcpStore.servers.first { $0.id == id }
        }

        private func serverEnabledBinding(_ id: String) -> Binding<Bool> {
            Binding(
                get: { server(id)?.enabled ?? false },
                set: { mcpStore.setServerEnabled(id: id, enabled: $0) }
            )
        }

        private func serverStatus(_ id: String) -> String {
            server(id)?.statusText(now: Date(), showsErrorDetail: true) ?? ""
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
