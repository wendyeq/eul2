//
//  GpuStore.swift
//  eul
//
//  Created by Gao Sun on 2021/1/23.
//  Copyright © 2021 Gao Sun. All rights reserved.
//

import Combine
import Foundation
import SharedLibrary
import SwiftUI
import WidgetKit

class GpuStore: ObservableObject, Refreshable {
    private var activeCancellable: AnyCancellable?

    @ObservedObject var componentsStore = SharedStore.components
    @ObservedObject var menuComponentsStore = SharedStore.menuComponents

    @Published var gpus = [GPU]()
    @Published var gpuStatistics = [GPU.Statistic]()
    @Published var usageHistory: [Double] = []
    @Published var gpuPowerW: Double?

    var usageAverage: Double? {
        let stats = gpus.compactMap { getStatustic(for: $0) }
        guard stats.count > 0 else {
            return nil
        }
        return Double(stats.reduce(0) { $0 + $1.usagePercentage }) / Double(stats.count)
    }

    var usageAverageString: String? {
        guard let average = usageAverage else {
            return nil
        }
        return "\(String(format: "%.0f", average))%"
    }

    var temperatureAverage: Double? {
        let temps = gpus.compactMap { getStatustic(for: $0)?.temperature }
        guard temps.count > 0 else {
            return nil
        }
        return temps.reduce(0) { $0 + $1 } / Double(temps.count)
    }

    func getStatustic(for gpu: GPU) -> GPU.Statistic? {
        gpuStatistics.first { $0.id == gpu.id }
    }

    init() {
        gpus = GPU.snapshot()?.gpus ?? []
        initObserver(for: .StoreShouldRefresh)
        // refresh immediately to prevent "N/A"
        activeCancellable = Publishers
            .CombineLatest(componentsStore.$activeComponents, menuComponentsStore.$activeComponents)
            .sink { _ in
                DispatchQueue.main.async {
                    self.refresh()
                }
            }
    }

    @objc func refresh() {
        let gpuVisible = componentsStore.activeComponents.contains(.GPU)
            || menuComponentsStore.activeComponents.contains(.GPU)

        if let snapshot = GPU.snapshot() {
            if !snapshot.gpus.isEmpty {
                gpus = snapshot.gpus
            }
            gpuStatistics = snapshot.statistics
        } else {
            gpuStatistics = []
        }
        gpuPowerW = SmcControl.shared.gpuPowerW
        if gpuVisible {
            usageHistory = (usageHistory + [usageAverage ?? 0]).suffix(LineChart.defaultMaxPointCount)
        } else {
            usageHistory = []
        }
        Print(
            "GpuStore models",
            gpus.map(\.model),
            "cores",
            gpus.map { $0.coreCount as Any },
            "mem",
            gpus.map { $0.inUseSystemMemory as Any },
            "PG0C",
            gpuPowerW as Any,
            "usage",
            usageAverageString as Any,
            "temp",
            temperatureAverage as Any
        )
        writeToContainer()
    }

    func writeToContainer() {
        Container.set(GpuEntry(
            usage: usageAverage,
            temp: temperatureAverage,
            powerW: gpuPowerW
        ))
        if #available(OSX 11, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: GpuEntry.kind)
        }
    }
}
