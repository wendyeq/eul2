import SwiftUI

struct McpMenuBlockView: View {
    @EnvironmentObject var mcpStore: McpStore
    @Environment(\.menuCompactLayout) private var menuCompactLayout

    var body: some View {
        VStack(alignment: .leading, spacing: menuCompactLayout ? MenuExpandedLayout.sectionSpacing : 8) {
            HStack(alignment: .center, spacing: 6) {
                MenuSectionHeader(title: "component.mcp", iconName: "MCP")
                Text(hubMessage)
                    .secondaryDisplayText()
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            if mcpStore.servers.isEmpty {
                Text("mcp.empty".localized())
                    .secondaryDisplayText()
            } else {
                ForEach(mcpStore.servers) { server in
                    serverRow(server)
                }
            }
        }
        .menuBlock()
    }

    private var hubMessage: String {
        if let error = mcpStore.lastError, !error.isEmpty {
            return "mcp.failed".localized()
        }
        return mcpStore.listening ? "mcp.listening".localized() : "mcp.stopped".localized()
    }

    @ViewBuilder
    private func serverRow(_ server: McpServerStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(server.id)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(statusText(server, now: context.date))
                    .secondaryDisplayText()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { server.enabled },
                set: { mcpStore.setServerEnabled(id: server.id, enabled: $0) }
            ))
                .toggleStyle(.checkbox)
                .controlSize(.mini)
        }
        .frame(width: MenuMetricGrid.rowWidth, alignment: .leading)
    }

    private func statusText(_ server: McpServerStatus, now: Date) -> String {
        server.statusText(now: now)
    }
}
