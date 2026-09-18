//
//  BatteryView.swift
//  eul
//
//  Created by Gao Sun on 2020/8/7.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import SharedLibrary
import SwiftUI

struct BatteryView: View {
    @EnvironmentObject var batteryStore: BatteryStore
    @EnvironmentObject var componentConfigStore: ComponentConfigStore
    @EnvironmentObject var textStore: ComponentsStore<BatteryTextComponent>

    var config: EulComponentConfig {
        componentConfigStore[.Battery]
    }

    var texts: [String] {
        textStore.activeComponents.map {
            switch $0 {
            case .percentage:
                return batteryStore.charge.percentageString
            case .mah:
                return "\(batteryStore.capacity) mAh"
            case .timeRemaining:
                return batteryStore.timeRemaining
            }
        }
    }

    private var powerStateText: String {
        if batteryStore.io.isCharging {
            return "battery.is_charging".localized()
        }
        if batteryStore.acPowered {
            return "battery.power_source.acPower".localized()
        }
        return "battery.power_source.battery".localized()
    }

    var body: some View {
        HStack(spacing: 6) {
            if config.showIcon {
                BatteryIconView(
                    isCharging: batteryStore.io.isCharging,
                    charge: batteryStore.charge,
                    acPowered: batteryStore.acPowered
                )
                .accessibilityHidden(true)
            }
            if textStore.showComponents {
                StatusBarTextView(texts: texts)
                    .stableWidth()
            }
        }
        .statusBarAccessibility(componentKey: "component.battery", values: [powerStateText] + texts)
    }
}
