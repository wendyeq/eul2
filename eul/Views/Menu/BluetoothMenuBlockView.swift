//
//  BluetoothMenuBlockView.swift
//  eul
//
//  Created by Gao Sun on 2021/1/18.
//  Copyright © 2021 Gao Sun. All rights reserved.
//

import SharedLibrary
import SwiftUI

struct BluetoothRowView: View {
    let device: BluetoothDevice

    var body: some View {
        HStack(spacing: 8) {
            Text(device.displayName)
                .secondaryDisplayText()
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isStaticText)
                .accessibilityLabel(device.displayName)
            if let batteryPercent = device.batteryPercent {
                Text("\(batteryPercent)%")
                    .displayText()
                    .metricAccessibility(titleKey: "battery.charge", value: "\(batteryPercent)%")
            }
            if let batteryPercent = device.batteryPercentLeft {
                compactPercent(titleKey: "bluetooth.left", label: "L", percent: batteryPercent)
            }
            if let batteryPercent = device.batteryPercentRight {
                compactPercent(titleKey: "bluetooth.right", label: "R", percent: batteryPercent)
            }
            if let batteryPercent = device.batteryPercentCase {
                compactPercent(titleKey: "bluetooth.case", label: "C", percent: batteryPercent)
            }
        }
    }

    private func compactPercent(titleKey: String, label: String, percent: Int) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .miniSection()
            Text("\(percent)%")
                .displayText()
        }
        .metricAccessibility(titleKey: titleKey, value: "\(percent)%")
    }
}

struct BluetoothMenuBlockView: View {
    @EnvironmentObject var bluetoothStore: BluetoothStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuSectionHeader(title: "bluetooth", iconName: "Bluetooth")
            if bluetoothStore.devices.count == 0 {
                Text("ui.empty".localized())
                    .placeholder()
                    .padding(.bottom, 4)
            }
            ForEach(bluetoothStore.devices) {
                BluetoothRowView(device: $0)
            }
        }
        .padding(.top, 2)
        .menuBlock()
        .onAppear {
            bluetoothStore.fetch()
        }
    }
}
