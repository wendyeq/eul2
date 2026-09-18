//
//  NetworkMenuBlockMenuView.swift
//  eul
//
//  Created by Gao Sun on 2020/10/17.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import SharedLibrary
import SwiftUI

struct NetworkMenuBlockMenuView: View {
    @EnvironmentObject var preferenceStore: PreferenceStore
    @EnvironmentObject var networkStore: NetworkStore
    @EnvironmentObject var networkTopStore: NetworkTopStore
    @Environment(\.menuCompactLayout) private var menuCompactLayout

    /// Row 1: 网络 | Wi-Fi (temp) | 上传 | 下载 — column-aligned with row 2 totals.
    private var networkLiveMetricRow: some View {
        HStack(alignment: .top, spacing: MenuMetricGrid.columnSpacing) {
            MenuSectionHeader(title: "network", iconName: "Network")
                .frame(width: MenuMetricGrid.columnWidth, alignment: .leading)

            networkMetricColumn(
                networkStore.wifiModuleTemperature.map {
                    ("temp.wifi", SmcControl.shared.formatTemp($0))
                }
            )
            networkMetricColumn(("network.out", networkStore.outSpeed))
            networkMetricColumn(("network.in", networkStore.inSpeed))
        }
        .frame(width: MenuMetricGrid.rowWidth, alignment: .leading)
    }

    @ViewBuilder
    private func networkMetricColumn(_ item: (title: String, value: String)?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let item {
                Text(item.title.localized())
                    .miniSection()
                    .lineLimit(1)
                Text(item.value)
                    .displayText()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: MenuMetricGrid.columnWidth, alignment: .leading)
        .accessibilityHidden(item == nil)
        .modifier(OptionalMetricAccessibility(item: item))
    }

    var body: some View {
        VStack(spacing: menuCompactLayout ? MenuExpandedLayout.sectionSpacing : 4) {
            networkLiveMetricRow
            SeparatorView(menuSection: menuCompactLayout)
            CompactQuadSectionRow(
                c0: ("network.today.out", networkStore.todayOutTotal),
                c1: ("network.today.in", networkStore.todayInTotal),
                c2: ("network.boot.out", networkStore.bootOutTotal),
                c3: ("network.boot.in", networkStore.bootInTotal)
            )
            if preferenceStore.showNetworkTopActivities {
                SeparatorView(menuSection: menuCompactLayout)
                // FIXME: multi thread with same pid
                VStack(spacing: MenuExpandedLayout.processListSpacing) {
                    ForEach(networkTopStore.processes.prefix(3)) { process in
                        ProcessRowView(
                            section: "network",
                            process: process,
                            expandedStatsWidth: MenuExpandedProcessRow.networkStatsWidth
                        ) { AnyView(
                            HStack(spacing: 4) {
                                Text(ByteUnit(process.value.outSpeedInByte).readable)
                                    .displayText()
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                Text(ByteUnit(process.value.inSpeedInByte).readable)
                                    .displayText()
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .frame(width: MenuExpandedProcessRow.networkStatsWidth, alignment: .trailing)
                        ) }
                    }
                    if networkTopStore.processes.count == 0 {
                        Spacer()
                        Text("network.no_activity".localized())
                            .secondaryDisplayText()
                        Spacer()
                    }
                }
                .frame(minHeight: 58, alignment: .top)
            }
        }
        .menuBlock()
    }
}
