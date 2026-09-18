//
//  BluetoothDevice.swift
//  eul
//
//  Created by Gao Sun on 2021/1/22.
//  Copyright © 2021 Gao Sun. All rights reserved.
//

import Foundation
import IOBluetooth

struct BluetoothDevice: Identifiable {
    let ioDevice: IOBluetoothDevice
    /// 0-100, straight from IORegistry. Render it as-is.
    var batteryPercent: Int?
    /// 0-100, parsed out of system_profiler's `"54%"` strings. Only AirPods-style
    /// accessories report these, and they never report `batteryPercent`.
    var batteryPercentLeft: Int?
    var batteryPercentRight: Int?
    var batteryPercentCase: Int?

    var id: String {
        address
    }

    var address: String {
        ioDevice.addressString
    }

    var displayName: String {
        ioDevice.nameOrAddress
    }
}
