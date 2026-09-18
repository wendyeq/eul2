//
//  CpuMenuBlockView.swift
//  eul
//
//  Created by Gao Sun on 2020/9/20.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import SharedLibrary
import SwiftUI

struct CpuMenuBlockView: View {
    @EnvironmentObject var preferenceStore: PreferenceStore
    @EnvironmentObject var cpuStore: CpuStore
    @EnvironmentObject var cpuTopStore: TopStore
    @Environment(\.menuCompactLayout) private var menuCompactLayout

    private func clusterUsageString(_ usage: Double, freq: String?) -> String {
        let usageText = String(format: "%.0f%%", usage)
        guard let freq = freq else { return usageText }
        return "\(usageText) · \(freq)"
    }

    private func usageRowColumn(
        _ index: Int,
        usageCPU: (system: Double, user: Double, idle: Double, nice: Double)
    ) -> (title: String, value: String) {
        switch preferenceStore.cpuMenuDisplay {
        case .usagePercentage:
            switch index {
            case 0:
                return ("cpu.system", String(format: "%.1f%%", usageCPU.system))
            case 1:
                return ("cpu.user", String(format: "%.1f%%", usageCPU.user))
            default:
                return ("cpu.nice", String(format: "%.1f%%", usageCPU.nice))
            }
        case .loadAverage:
            switch index {
            case 0:
                return ("1 min", cpuStore.loadAverage1MinString)
            case 1:
                return ("5 min", cpuStore.loadAverage5MinString)
            default:
                return ("15 min", cpuStore.loadAverage15MinString)
            }
        }
    }

    var body: some View {
        VStack(spacing: MenuExpandedLayout.sectionVStackSpacing(compact: menuCompactLayout)) {
            HStack(alignment: .center) {
                MenuSectionHeader(title: "component.cpu", iconName: "CPU")
                Spacer()
                if preferenceStore.cpuMenuDisplay == .usagePercentage {
                    Text(cpuStore.usageString)
                        .displayText()
                }
                LineChart(points: cpuStore.usageHistory, frame: CGSize(width: 35, height: 20))
            }
            cpuStore.usageCPU.map { usageCPU in
                VStack(spacing: MenuExpandedLayout.metricRowSpacing(compact: menuCompactLayout)) {
                    SeparatorView(menuSection: menuCompactLayout)
                    CompactQuadSectionRow(
                        c0: usageRowColumn(0, usageCPU: usageCPU),
                        c1: usageRowColumn(1, usageCPU: usageCPU),
                        c2: usageRowColumn(2, usageCPU: usageCPU),
                        c3: cpuStore.temp.map { ("cpu.temperature", SmcControl.shared.formatTemp($0)) }
                    )
                    if cpuStore.systemPowerW != nil
                        || cpuStore.cpuPowerW != nil
                        || cpuStore.palmRestTemp != nil
                        || cpuStore.enclosureTemp != nil
                    {
                        CompactQuadSectionRow(
                            c0: cpuStore.systemPowerW.map { ("power.system", SmcControl.shared.formatPower($0)) },
                            c1: cpuStore.cpuPowerW.map { ("power.cpu", SmcControl.shared.formatPower($0)) },
                            c2: cpuStore.palmRestTemp.map { ("temp.palm_rest", SmcControl.shared.formatTemp($0)) },
                            c3: cpuStore.enclosureTemp.map { ("temp.enclosure", SmcControl.shared.formatTemp($0)) }
                        )
                    }
                    if cpuStore.usageEPercent != nil
                        || cpuStore.usagePPercent != nil
                        || cpuStore.cpuThrottleLabel != nil
                        || cpuStore.aneActivityLabel != nil
                    {
                        CompactQuadSectionRow(
                            c0: cpuStore.usageEPercent.map {
                                ("cpu.cluster.e", clusterUsageString($0, freq: cpuStore.freqEString))
                            },
                            c1: cpuStore.usagePPercent.map {
                                ("cpu.cluster.p", clusterUsageString($0, freq: cpuStore.freqPString))
                            },
                            c2: cpuStore.cpuThrottleLabel.map { ("cpu.throttle", $0) },
                            c3: cpuStore.aneActivityLabel.map { ("ane.title", $0) }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if preferenceStore.showCPUTopActivities {
                SeparatorView(menuSection: menuCompactLayout)
                VStack(spacing: MenuExpandedLayout.processListSpacing) {
                    ForEach(cpuTopStore.cpuTopProcesses) {
                        ProcessRowView(section: "cpu", process: $0)
                    }
                    if !cpuTopStore.cpuDataAvailable {
                        Spacer()
                        Text("cpu.waiting_status_report".localized())
                            .secondaryDisplayText()
                        Spacer()
                    }
                }
                .frame(minHeight: 102, alignment: .top)
            }
        }
        .menuBlock()
    }
}
