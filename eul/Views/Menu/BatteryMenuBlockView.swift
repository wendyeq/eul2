//
//  BatteryMenuBlockView.swift
//  eul
//
//  Created by Gao Sun on 2020/9/20.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import SharedLibrary
import SwiftUI

struct BatteryMenuBlockView: View {
    @EnvironmentObject var batteryStore: BatteryStore
    var io: Info.Battery {
        batteryStore.io
    }

    private var batteryPowerStateText: String {
        if io.isCharging {
            return "battery.is_charging".localized()
        }
        if batteryStore.acPowered {
            return "battery.power_source.acPower".localized()
        }
        return "battery.power_source.battery".localized()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                MenuSectionHeader(title: "battery", iconName: "Battery")
                Spacer()
                if io.isCharging && io.timeToFullCharge >= 0 {
                    Text(io.timeToFullCharge.readableTimeInMin)
                        .displayText()
                    Text("battery.to_full_charge".localized())
                        .miniSection()
                        .padding(.trailing, 4)
                }
                if !io.isCharging && !io.isCharged && io.timeToEmpty >= 0 {
                    Text(io.timeToEmpty.readableTimeInMin)
                        .displayText()
                    Text("battery.to_empty".localized())
                        .miniSection()
                        .padding(.trailing, 4)
                }
                BatteryIconView(
                    size: 15,
                    isCharging: batteryStore.io.isCharging,
                    charge: batteryStore.charge,
                    acPowered: batteryStore.acPowered
                )
                .accessibilityHidden(true)
                Text(batteryStore.charge.percentageString)
                    .displayText()
                    .accessibilityLabel(batteryPowerStateText)
                    .accessibilityValue(batteryStore.charge.percentageString)
            }
            HStack {
                Text("battery.health".localized())
                    .miniSection()
                Text(batteryStore.health.percentageString)
                    .displayText()
                if batteryStore.maxCapacity > 0 {
                    Spacer()
                    Text("battery.max_capacity".localized())
                        .miniSection()
                    Text("\(batteryStore.maxCapacity.description) mAh")
                        .displayText()
                }
                if batteryStore.designCapacity > 0 {
                    Spacer()
                    Text("battery.design_capacity".localized())
                        .miniSection()
                    Text("\(batteryStore.designCapacity.description) mAh")
                        .displayText()
                }
            }
            .padding(.top, 4)
            SeparatorView()
            CompactQuadSectionRow(
                c0: ("battery.power_source", io.powerSource.description),
                c1: ("battery.is_charging", "menu.\(io.isCharging ? "yes" : "no")".localized()),
                c2: ("battery.cycle_count", batteryStore.cycleCount.description),
                c3: ("battery.condition", io.condition.description)
            )
        }
        .menuBlock()
    }
}
