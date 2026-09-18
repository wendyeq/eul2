//
//  ProcessRowView.swift
//  eul
//
//  Created by Gao Sun on 2020/10/17.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import SwiftUI

struct ProcessRowView<Usage: ProcessUsage>: View {
    let section: String
    let process: Usage
    var expandedStatsWidth: CGFloat = MenuExpandedProcessRow.cpuStatWidth
    var valueViewBuilder: (() -> AnyView)? = nil

    @EnvironmentObject private var uiStore: UIStore
    @Environment(\.statusMenuExpandedChrome) private var expandedChrome

    private var isPinnedToListTop: Bool {
        uiStore.isMenuProcessPinned(section: section, pid: process.pid)
    }

    private var expandedTrailingWidth: CGFloat {
        MenuExpandedProcessRow.trailingClusterWidth(statsWidth: expandedStatsWidth)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(process.displayName)
                .secondaryDisplayText()
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)

            trailingCluster
                .frame(
                    width: expandedChrome ? expandedTrailingWidth : nil,
                    alignment: .trailing
                )
        }
        .padding(.vertical, expandedChrome ? 3 : 0)
        .frame(minHeight: expandedChrome ? MenuExpandedLayout.processRowMinHeight : nil)
        .frame(width: MenuMetricGrid.rowWidth, alignment: .leading)
    }

    @ViewBuilder
    private var trailingCluster: some View {
        if expandedChrome {
            expandedTrailingCluster
        } else {
            legacyTrailingCluster
        }
    }

    private var legacyTrailingCluster: some View {
        HStack(spacing: 4) {
            Group {
                if let builder = valueViewBuilder {
                    builder()
                } else {
                    Text(defaultStatText)
                        .displayText()
                        .lineLimit(1)
                        .frame(width: 35, alignment: .trailing)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .allowsHitTesting(false)

            processActionButtons
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var expandedTrailingCluster: some View {
        HStack(spacing: MenuExpandedProcessRow.statsToActionsSpacing) {
            Group {
                if let builder = valueViewBuilder {
                    builder()
                } else {
                    Text(defaultStatText)
                        .processMenuStatTextStyle()
                }
            }
            .frame(width: expandedStatsWidth, alignment: .trailing)
            .allowsHitTesting(false)

            processActionButtons
        }
        .frame(width: expandedTrailingWidth, alignment: .trailing)
    }

    private var defaultStatText: String {
        if let percent = process.value as? Double {
            return percent.menuStatPercentString
        }
        return process.value.description
    }

    private var processActionButtons: some View {
        HStack(spacing: MenuExpandedProcessRow.actionSpacing) {
            MenuActionButtonView(
                id: "\(section)-\(process.pid)-list-pin",
                systemImage: isPinnedToListTop ? "pin.fill" : "arrow.up.forward.app",
                toolTip: "process.bring_to_front",
                expandedKeepsMenuOpen: true,
                action: toggleProcessListPin
            )
            MenuActionButtonView(
                id: "\(section)-\(process.pid)-open",
                systemImage: "folder",
                toolTip: "process.reveal_in_finder"
            ) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: process.command, isDirectory: false)])
            }
            MenuActionButtonView(
                id: "\(section)-\(process.pid)-terminate",
                systemImage: "xmark",
                toolTip: "process.terminate"
            ) {
                let alert = NSAlert()
                alert.messageText = "process.terminate_alert.text.%@".localizedFormat(process.displayName)
                alert.informativeText = "process.terminate_alert.command.%@".localizedFormat(process.command)
                alert.alertStyle = .warning
                alert.addButton(withTitle: "process.terminate_alert.cancel".localized())
                alert.addButton(withTitle: "process.force_terminate".localized())
                alert.addButton(withTitle: "process.terminate".localized())
                NSApp.activate(ignoringOtherApps: true)

                let result = alert.runModal()
                if result == .alertSecondButtonReturn {
                    if let runningApp = process.runningApp {
                        runningApp.terminate()
                    } else {
                        shell("kill \(process.pid)")
                    }
                }
                if result == .alertThirdButtonReturn {
                    if let runningApp = process.runningApp {
                        runningApp.forceTerminate()
                    } else {
                        shell("kill -9 \(process.pid)")
                    }
                }
            }
        }
        .zIndex(1)
    }

    private func toggleProcessListPin() {
        uiStore.togglePinnedMenuProcess(section: section, pid: process.pid)
    }
}

private extension Text {
    func processMenuStatTextStyle() -> some View {
        displayText()
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
