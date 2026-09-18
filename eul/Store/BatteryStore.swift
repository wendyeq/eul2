//
//  BatteryStore.swift
//  eul
//
//  Created by Gao Sun on 2020/8/7.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Foundation
import SharedLibrary
import SystemKit
import WidgetKit

class BatteryStore: ObservableObject, Refreshable {
    private var battery = Battery()

    var io = Info.Battery()

    @Published var isValid = true

    @Published var acPowered = false
    @Published var charged = false
    @Published var charging = false
    @Published var capacity = 0
    @Published var maxCapacity = 0
    @Published var designCapacity = 0
    @Published var cycleCount = 0
    @Published var timeRemaining = "∞"

    var charge: Double {
        io.currentCharge
    }

    var health: Double {
        Double(maxCapacity) / Double(designCapacity)
    }

    /// Apple Silicon reports the top-level `CurrentCapacity` and `MaxCapacity` as
    /// percentages and drops `DesignCapacity` altogether, which is why SystemKit
    /// reads 0 and the mAh labels were wrong. The real mAh figures live in the
    /// `BatteryData` sub-dictionary.
    private static func capacities() -> (current: Int, max: Int, design: Int)? {
        guard
            let properties = IOHelper.getPropertyList(for: "AppleSmartBattery")?.first,
            let batteryData = properties["BatteryData"] as? [String: Any],
            let design = batteryData["DesignCapacity"] as? Int,
            let max = batteryData["NominalChargeCapacity"] as? Int
        else {
            return nil
        }

        return (batteryData["RemainingCapacity"] as? Int ?? 0, max, design)
    }

    @objc func refresh() {
        io = Info.Battery()

        guard battery.open() == kIOReturnSuccess else {
            isValid = false
            return
        }

        isValid = true

        acPowered = battery.isACPowered()
        charged = battery.isCharged()
        charging = battery.isCharging()
        (capacity, maxCapacity, designCapacity) = Self.capacities() ?? (0, 0, 0)
        cycleCount = battery.cycleCount()
        if io.powerSource == .battery, io.timeToEmpty >= 0 {
            timeRemaining = io.timeToEmpty.colonTimeFromMinutes
        } else {
            timeRemaining = "∞"
        }
        _ = battery.close()
        Print(
            "🔋 battery health",
            health.percentageString,
            "capacity",
            capacity,
            "max",
            maxCapacity,
            "design",
            designCapacity,
            "cycles",
            cycleCount
        )
        writeToContainer()
    }

    func writeToContainer() {
        Container.set(BatteryEntry(
            isCharging: charging, acPowered: acPowered, charge: charge, capacity: capacity, maxCapacity: maxCapacity, designCapacity: designCapacity, cycleCount: cycleCount, condition: io.condition
        ))
        if #available(OSX 11, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: BatteryEntry.kind)
        }
    }

    init() {
        initObserver(for: .StoreShouldRefresh)
        refresh()
    }
}
