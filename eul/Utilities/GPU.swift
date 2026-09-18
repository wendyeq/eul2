//
//  GPU.swift
//  eul
//
//  Created by Gao Sun on 2021/1/23.
//  Copyright © 2021 Gao Sun. All rights reserved.
//

import Foundation

struct GPU: Identifiable {
    var id: String
    var model: String
    var coreCount: Int?
    var inUseSystemMemory: UInt64?
}

extension GPU {
    struct Statistic {
        var id: String
        var usagePercentage: Int
        var temperature: Double?
        var coreClock: Int?
        var memoryClock: Int?
    }
}

extension GPU {
    // https://stackoverflow.com/questions/10110658/programmatically-get-gpu-percent-usage-in-os-x/22440235#22440235
    // https://github.com/exelban/stats/blob/master/Modules/GPU/reader.swift
    static func snapshot() -> (gpus: [GPU], statistics: [Statistic])? {
        guard let list = IOHelper.getPropertyList(for: kIOAcceleratorClassName) else {
            return nil
        }

        var gpus = [GPU]()
        var statistics = [Statistic]()
        gpus.reserveCapacity(list.count)

        for (index, properties) in list.enumerated() {
            let id = "gpu-\(index)"
            let perf = properties["PerformanceStatistics"] as? [String: Any]
            let memory = perf?["In use system memory"] as? UInt64
                ?? (perf?["In use system memory"] as? Int).map(UInt64.init)

            gpus.append(GPU(
                id: id,
                model: model(of: properties),
                coreCount: properties["gpu-core-count"] as? Int,
                inUseSystemMemory: (memory ?? 0) > 0 ? memory : nil
            ))

            guard
                let perf = perf,
                let usagePercentage = perf["Device Utilization %"] as? Int ?? perf["GPU Activity(%)"] as? Int
            else {
                continue
            }

            Print("📊 statistics", perf)

            statistics.append(Statistic(
                id: id,
                usagePercentage: usagePercentage,
                temperature: perf["Temperature(C)"] as? Double ?? SmcControl.shared.gpuTemperature,
                coreClock: perf["Core Clock(MHz)"] as? Int,
                memoryClock: perf["Memory Clock(MHz)"] as? Int
            ))
        }

        return (gpus, statistics)
    }

    /// `model` is a string on Apple Silicon, but IORegistry serves it as
    /// null-terminated bytes on some machines.
    private static func model(of properties: NSDictionary) -> String {
        if let model = properties["model"] as? String {
            return model
        }
        if
            let data = properties["model"] as? Data,
            let model = String(data: data, encoding: .utf8)
        {
            return model.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        }
        return properties["IOClass"] as? String ?? "GPU"
    }
}
