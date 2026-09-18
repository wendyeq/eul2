//
//  GpuMenuBlockView.swift
//  eul
//
//  Created by Gao Sun on 2021/1/24.
//  Copyright © 2021 Gao Sun. All rights reserved.
//

import SharedLibrary
import SwiftUI

struct GpuMenuBlockView: View {
    @EnvironmentObject var gpuStore: GpuStore
    @Environment(\.menuCompactLayout) private var menuCompactLayout

    private func gpuTitle(_ gpu: GPU) -> String {
        guard let cores = gpu.coreCount, cores > 0 else {
            return gpu.model
        }
        return "\(gpu.model) · \(cores) \("gpu.cores.unit".localized())"
    }

    func toGHzString(_ mhz: Int) -> String {
        String(format: "%.1f", Double(mhz) / 1000) + "GHz"
    }

    var body: some View {
        VStack(spacing: MenuExpandedLayout.sectionVStackSpacing(compact: menuCompactLayout)) {
            HStack(alignment: .center, spacing: 6) {
                MenuSectionHeader(title: "component.gpu", iconName: "GPU")
                gpuStore.gpus.first.map { gpu in
                    Text(gpuTitle(gpu))
                        .secondaryDisplayText()
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                LineChart(points: gpuStore.usageHistory, frame: CGSize(width: 35, height: 20))
            }
            ForEach(Array(gpuStore.gpus.enumerated()), id: \.element.id) { index, gpu in
                VStack(alignment: .leading, spacing: 4) {
                    if index > 0 {
                        Text(gpuTitle(gpu))
                            .secondaryDisplayText()
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    let statistic = gpuStore.getStatustic(for: gpu)
                    CompactQuadSectionRow(
                        c0: ("gpu.usage", statistic.map { "\($0.usagePercentage)%" } ?? "N/A"),
                        c1: gpu.inUseSystemMemory.map { ("gpu.unified_memory.short", ByteUnit($0).readable) },
                        c2: statistic?.temperature.map { ("cpu.temperature", $0.temperatureString) },
                        c3: gpuStore.gpuPowerW.map { ("power.gpu.short", SmcControl.shared.formatPower($0)) }
                    )
                    if statistic?.coreClock != nil || statistic?.memoryClock != nil {
                        CompactQuadSectionRow(
                            c0: statistic?.coreClock.map { ("gpu.clock.core", toGHzString($0)) },
                            c1: statistic?.memoryClock.map { ("gpu.clock.memory", toGHzString($0)) },
                            c2: nil,
                            c3: nil
                        )
                    }
                }
            }
        }
        .padding(.top, 2)
        .menuBlock()
    }
}
