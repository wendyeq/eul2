//
//  NetworkStore.swift
//  eul
//
//  Created by Gao Sun on 2020/8/9.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Foundation
import SharedLibrary
import WidgetKit

class NetworkStore: ObservableObject, Refreshable {
    private var networkUsageHasBeenSet = true
    private var lastTimestamp: TimeInterval
    private let trafficAccumulator = NetworkTrafficAccumulator()

    @Published var networkUsage = Info.NetworkUsage(inBytes: 0, outBytes: 0)
    @Published private(set) var todayInBytes: UInt64 = 0
    @Published private(set) var todayOutBytes: UInt64 = 0
    @Published private(set) var bootInBytes: UInt64 = 0
    @Published private(set) var bootOutBytes: UInt64 = 0
    @Published var ports = [Info.NetworkPort]()
    @Published var currentActivePort: Info.NetworkPort?

    @Published var inSpeedInByte: Double = 0
    @Published var outSpeedInByte: Double = 0
    @Published var wifiModuleTemperature: Double?

    var config: EulComponentConfig {
        SharedStore.componentConfig[EulComponent.Network]
    }

    var inSpeed: String {
        ByteUnit(inSpeedInByte).readable + "/s"
    }

    var outSpeed: String {
        ByteUnit(outSpeedInByte).readable + "/s"
    }

    var todayInTotal: String {
        ByteUnit(todayInBytes).readable
    }

    var todayOutTotal: String {
        ByteUnit(todayOutBytes).readable
    }

    var bootInTotal: String {
        ByteUnit(bootInBytes).readable
    }

    var bootOutTotal: String {
        ByteUnit(bootOutBytes).readable
    }

    var autoPortDesscription: String {
        guard let currentActivePort = currentActivePort else {
            return "network.port.auto".localized()
        }

        return "\("network.port.auto".localized()) (\(currentActivePort.device))"
    }

    @objc func refresh() {
        wifiModuleTemperature = SmcControl.shared.wifiModuleTemperature
        Print("NetworkStore WiFi", wifiModuleTemperature as Any)

        guard networkUsageHasBeenSet else {
            return
        }

        networkUsageHasBeenSet = false

        Info.getNetworkUsage(forDevice: config.networkPortSelection.nilIfEmpty) { [self] current, ports, currentActivePort, device in
            let time = Date().timeIntervalSince1970

            if networkUsage.inBytes > 0, current.inBytes >= networkUsage.inBytes {
                inSpeedInByte = Double(current.inBytes - networkUsage.inBytes) / (time - lastTimestamp)
            } else {
                inSpeedInByte = 0
            }

            if networkUsage.outBytes > 0, current.outBytes >= networkUsage.outBytes {
                outSpeedInByte = Double(current.outBytes - networkUsage.outBytes) / (time - lastTimestamp)
            } else {
                outSpeedInByte = 0
            }

            lastTimestamp = time
            networkUsage = current
            self.ports = ports
            self.currentActivePort = currentActivePort
            let totals = trafficAccumulator.ingest(device: device, usage: current)
            todayInBytes = totals.todayInBytes
            todayOutBytes = totals.todayOutBytes
            bootInBytes = totals.bootInBytes
            bootOutBytes = totals.bootOutBytes
            writeToContainer()
            networkUsageHasBeenSet = true
        }
    }

    func writeToContainer() {
        Container.set(NetworkEntry(inSpeedInByte: inSpeedInByte, outSpeedInByte: outSpeedInByte))
        if #available(OSX 11, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: NetworkEntry.kind)
        }
    }

    init() {
        lastTimestamp = Date().timeIntervalSince1970
        let initialTotals = trafficAccumulator.snapshot()
        todayInBytes = initialTotals.todayInBytes
        todayOutBytes = initialTotals.todayOutBytes
        bootInBytes = initialTotals.bootInBytes
        bootOutBytes = initialTotals.bootOutBytes
        initObserver(for: .NetworkShouldRefresh)
        initObserver(for: .StoreShouldRefresh)
    }
}
