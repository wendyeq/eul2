//
//  MemoryMenuBlockView.swift
//  eul
//
//  Created by Gao Sun on 2020/9/20.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import SharedLibrary
import SwiftUI

struct MemoryMenuBlockView: View {
    @EnvironmentObject var preferenceStore: PreferenceStore
    @EnvironmentObject var memoryStore: MemoryStore
    @EnvironmentObject var memoryTopStore: TopStore
    @Environment(\.menuCompactLayout) private var menuCompactLayout

    private func headerMemoryString(_ gigabytes: Double) -> String {
        gigabytes.memoryString.replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: menuCompactLayout ? MenuExpandedLayout.sectionSpacing : 4) {
            HStack(alignment: .center) {
                MenuSectionHeader(title: "memory", iconName: "Memory")
                Spacer(minLength: 8)
                ProgressBarView(
                    width: 35,
                    percentage: CGFloat(memoryStore.usedPercentage),
                    showText: false,
                    glassTrack: menuCompactLayout
                )
                .accessibilityLabel("memory.usage".localized())
            }
            SeparatorView(menuSection: menuCompactLayout)
            CompactQuadSectionRow(
                c0: ("memory.usage", headerMemoryString(memoryStore.used)),
                c1: ("memory.free", headerMemoryString(memoryStore.allFree)),
                c2: memoryStore.estimatedMemoryBandwidthGBs.map {
                    ("memory.bandwidth.estimate", String(format: "%d\u{00A0}GB/s", $0))
                },
                c3: memoryStore.vmPressureLevel.map {
                    ("memory.pressure", $0.valueLocalizationKey.localized())
                }
            )
            CompactQuadSectionRow(
                c0: ("memory.cached_files", headerMemoryString(memoryStore.cachedFiles)),
                c1: ("memory.app", headerMemoryString(memoryStore.appMemory)),
                c2: ("memory.wired", headerMemoryString(memoryStore.wired)),
                c3: ("memory.compressed", headerMemoryString(memoryStore.compressed))
            )
            if preferenceStore.showRAMTopActivities {
                SeparatorView(menuSection: menuCompactLayout)
                VStack(spacing: MenuExpandedLayout.processListSpacing) {
                    if !memoryTopStore.ramDataAvailable {
                        Spacer()
                        Text("cpu.waiting_status_report".localized())
                            .secondaryDisplayText()
                            .frame(maxWidth: .infinity, alignment: .center)
                        Spacer()
                    } else {
                        ForEach(memoryTopStore.ramTopProcesses) { process in
                            ProcessRowView(
                                section: "memory",
                                process: process,
                                expandedStatsWidth: MenuExpandedProcessRow.memoryStatsWidth
                            ) {
                                AnyView(
                                    HStack(spacing: 4) {
                                        Text("\(ByteUnit(megaBytes: process.usageAmount).readable)")
                                            .displayText()
                                            .monospacedDigit()
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                        Text(process.value.menuStatPercentString)
                                            .displayText()
                                            .monospacedDigit()
                                            .lineLimit(1)
                                            .fixedSize(horizontal: true, vertical: false)
                                    }
                                    .frame(width: MenuExpandedProcessRow.memoryStatsWidth, alignment: .trailing)
                                )
                            }
                        }
                    }
                }
                .frame(minHeight: 102, alignment: .top)
            }
        }
        .menuBlock()
    }
}
