//
//  CpuStore.swift
//  eul
//
//  Created by Gao Sun on 2020/6/27.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Foundation
import SharedLibrary
import SystemKit
import WidgetKit

class CpuStore: ObservableObject, Refreshable {
    @Published var temp: Double?
    @Published var usageCPU: (system: Double, user: Double, idle: Double, nice: Double)?
    @Published var loadAverage: [Double]?
    @Published var physicalCores = 0
    @Published var logicalCores = 0
    @Published var upTime: (days: Int, hrs: Int, mins: Int, secs: Int)?
    @Published var thermalLevel: System.ThermalLevel = .Unknown
    @Published var usageHistory: [Double] = []
    @Published var systemPowerW: Double?
    @Published var cpuPowerW: Double?
    @Published var palmRestTemp: Double?
    @Published var enclosureTemp: Double?
    @Published var usageEPercent: Double?
    @Published var usagePPercent: Double?
    @Published var freqEString: String?
    @Published var freqPString: String?
    @Published var cpuThrottleLabel: String?
    @Published var aneActivityLabel: String?

    var loadAverage1MinString: String {
        formatDouble(loadAverage?[safe: 0])
    }

    var loadAverage5MinString: String {
        formatDouble(loadAverage?[safe: 1])
    }

    var loadAverage15MinString: String {
        formatDouble(loadAverage?[safe: 2])
    }

    var usageString: String {
        guard let usage = usageCPU else {
            return "N/A"
        }
        return String(format: "%.0f%%", usage.system + usage.user)
    }

    var usage: Double? {
        guard let usageCPU = usageCPU else {
            return nil
        }
        return usageCPU.system + usageCPU.user
    }

    private func formatDouble(_ value: Double?) -> String {
        guard let value = value else {
            return "N/A"
        }
        return String(format: "%.2f", value)
    }

    private func getInfo() {
        physicalCores = System.physicalCores()
        logicalCores = System.logicalCores()
        upTime = System.uptime()
        thermalLevel = System.thermalLevel()
    }

    private func getUsage() {
        let usage = Info.system.usageCPU()
        usageCPU = usage
        loadAverage = System.loadAverage()
        usageHistory = (usageHistory + [usage.system + usage.user]).suffix(LineChart.defaultMaxPointCount)
    }

    private func getTemp() {
        temp = (SmcControl.shared.cpuCoreTemperature ?? 0) > 0
            ? SmcControl.shared.cpuCoreTemperature
            : SmcControl.shared.cpuEfficiencyTemperature
        palmRestTemp = SmcControl.shared.palmRestTemperature
        enclosureTemp = SmcControl.shared.enclosureTemperature
    }

    private func getPower() {
        systemPowerW = SmcControl.shared.systemPowerW
        cpuPowerW = SmcControl.shared.cpuPowerW
    }

    private func getAppleSiliconMetrics() {
        let cluster = AppleSiliconIOReport.shared.lastCluster
        usageEPercent = cluster.usageEPercent
        usagePPercent = cluster.usagePPercent
        freqEString = cluster.freqEMhz.map { AppleSiliconIOReport.formatFrequency(mhz: $0) }
        freqPString = cluster.freqPMhz.map { AppleSiliconIOReport.formatFrequency(mhz: $0) }
        cpuThrottleLabel = cluster.throttleLabel

        if let isActive = AppleSiliconIOReport.shared.lastANEActive {
            aneActivityLabel = isActive ? "ane.active".localized() : "ane.idle".localized()
        } else {
            aneActivityLabel = nil
        }
    }

    @objc func refresh() {
        getInfo()
        getUsage()
        getTemp()
        getPower()
        getAppleSiliconMetrics()
        Print(
            "CpuStore PSTR",
            systemPowerW as Any,
            "PP0C",
            cpuPowerW as Any,
            "palm",
            palmRestTemp as Any,
            "enclosure",
            enclosureTemp as Any,
            "E%",
            usageEPercent as Any,
            "P%",
            usagePPercent as Any,
            "EHz",
            freqEString as Any,
            "PHz",
            freqPString as Any,
            "Ppeak",
            AppleSiliconIOReport.shared.lastCluster.pPeakMhz as Any,
            "ANE",
            aneActivityLabel as Any
        )
        writeToContainer()
    }

    func writeToContainer() {
        Container.set(CpuEntry(
            temp: temp,
            usageSystem: usageCPU?.system,
            usageUser: usageCPU?.user,
            usageNice: usageCPU?.nice
        ))
        if #available(OSX 11, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: CpuEntry.kind)
        }
    }

    init() {
        initObserver(for: .StoreShouldRefresh)
    }
}
