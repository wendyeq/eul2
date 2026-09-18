//
//  BluetoothStore.swift
//  eul
//
//  Created by Gao Sun on 2021/1/18.
//  Copyright © 2021 Gao Sun. All rights reserved.
//

import Foundation
import IOBluetooth
import SwiftyJSON

class BluetoothStore: ObservableObject {
    private struct AccessoryBattery {
        var left: Int?
        var right: Int?
        var caseLevel: Int?

        var isEmpty: Bool {
            left == nil && right == nil && caseLevel == nil
        }
    }

    private static let hidEventServiceName = "AppleDeviceManagementHIDEventService"
    /// `system_profiler` spawns a process and costs ~100ms, so it never runs on
    /// the fetch path. Cached values are merged in immediately and refreshed in
    /// the background once stale.
    private static let accessoryCacheTTL: TimeInterval = 30

    @Published var devices: [BluetoothDevice] = []

    private var accessoryBatteries = [String: AccessoryBattery]()
    private var accessoryBatteriesReadAt: Date?
    private var isReadingAccessoryBatteries = false

    var connectedDevices: [BluetoothDevice] {
        devices.filter { $0.ioDevice.isConnected() }
    }

    /// macOS 27 dropped `DeviceCache` and `CoreBluetoothCache` from
    /// com.apple.bluetooth.plist, which killed both the plist battery lookup and
    /// the only source of CoreBluetooth peripheral UUIDs. `DeviceAddress` here is
    /// formatted exactly like `IOBluetoothDevice.addressString`.
    private func batteryPercentByAddress() -> [String: Int] {
        guard let propertyList = IOHelper.getPropertyList(for: Self.hidEventServiceName) else {
            return [:]
        }

        return propertyList.reduce(into: [String: Int]()) { result, properties in
            guard
                let address = properties["DeviceAddress"] as? String,
                let batteryPercent = properties["BatteryPercent"] as? Int
            else {
                return
            }
            result[Self.normalizedAddress(address)] = batteryPercent
        }
    }

    func fetch() {
        let batteryPercents = batteryPercentByAddress()

        devices = IOBluetoothDevice.pairedDevices()?.compactMap {
            guard let ioDevice = $0 as? IOBluetoothDevice, ioDevice.isConnected() else {
                return nil
            }
            return BluetoothDevice(
                ioDevice: ioDevice,
                batteryPercent: batteryPercents[Self.normalizedAddress(ioDevice.addressString)]
            )
        } ?? []

        applyAccessoryBatteries()
        readAccessoryBatteriesIfStale()
    }

    /// AirPods-style accessories are absent from IORegistry entirely; their only
    /// battery source is `system_profiler`.
    private func applyAccessoryBatteries() {
        devices = devices.map { device in
            var device = device
            let accessory = accessoryBatteries[Self.normalizedAddress(device.address)]
            device.batteryPercentLeft = accessory?.left
            device.batteryPercentRight = accessory?.right
            device.batteryPercentCase = accessory?.caseLevel
            return device
        }

        Print(
            "🔵🦷 connected devices",
            devices.map {
                "name=\($0.displayName), address=\($0.address), battery=\($0.batteryPercent as Any)"
                    + ", L=\($0.batteryPercentLeft as Any), R=\($0.batteryPercentRight as Any), C=\($0.batteryPercentCase as Any)"
            }
        )
    }

    private func readAccessoryBatteriesIfStale() {
        if let readAt = accessoryBatteriesReadAt, Date().timeIntervalSince(readAt) < Self.accessoryCacheTTL {
            return
        }
        guard !isReadingAccessoryBatteries else {
            return
        }
        isReadingAccessoryBatteries = true

        shellAsync("system_profiler -json SPBluetoothDataType") { [weak self] output in
            DispatchQueue.main.async {
                guard let self = self else {
                    return
                }
                self.isReadingAccessoryBatteries = false
                self.accessoryBatteriesReadAt = Date()

                guard let data = output?.data(using: .utf8) else {
                    return
                }
                self.accessoryBatteries = Self.parseAccessoryBatteries(data)
                self.applyAccessoryBatteries()
            }
        }
    }

    private static func parseAccessoryBatteries(_ data: Data) -> [String: AccessoryBattery] {
        guard let json = try? JSON(data: data) else {
            return [:]
        }

        var result = [String: AccessoryBattery]()
        for section in json["SPBluetoothDataType"].arrayValue {
            // Each entry is a single-key object whose key is the device name.
            for entry in section["device_connected"].arrayValue {
                for (_, device) in entry.dictionaryValue {
                    guard let address = device["device_address"].string else {
                        continue
                    }
                    let battery = AccessoryBattery(
                        left: percent(device["device_batteryLevelLeft"].string),
                        right: percent(device["device_batteryLevelRight"].string),
                        caseLevel: percent(device["device_batteryLevelCase"].string)
                    )
                    guard !battery.isEmpty else {
                        continue
                    }
                    result[normalizedAddress(address)] = battery
                }
            }
        }
        return result
    }

    /// system_profiler reports `EC:73:79:59:1F:16`, IOBluetooth reports
    /// `ec-73-79-59-1f-16`, and IORegistry matches IOBluetooth.
    private static func normalizedAddress(_ address: String) -> String {
        address.lowercased().replacingOccurrences(of: ":", with: "-")
    }

    /// system_profiler gives percentages as strings like `"54%"`.
    private static func percent(_ value: String?) -> Int? {
        guard let value = value?.trimmingCharacters(in: CharacterSet(charactersIn: "% ")) else {
            return nil
        }
        return Int(value)
    }

    init() {
        // Warm the accessory cache so the first popover already has values.
        readAccessoryBatteriesIfStale()

        // BluetoothMenuBlockView.onAppear is the only production caller of
        // fetch(), so nothing reads the battery until the menu is opened. Prime
        // it under --debug so the values are observable without the popover.
        if isDebug {
            fetch()
        }
    }
}
