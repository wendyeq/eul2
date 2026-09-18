//
//  MemoryVMPressure.swift
//  eul
//
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Foundation

enum MemoryVMPressureLevel: Int {
    case normal = 0
    case warning = 1
    case critical = 2

    var valueLocalizationKey: String {
        switch self {
        case .normal:
            return "memory.pressure.normal"
        case .warning:
            return "memory.pressure.warning"
        case .critical:
            return "memory.pressure.critical"
        }
    }
}

enum MemoryVMPressure {
    /// Public sysctl used by system memory status (same family as Activity Monitor pressure).
    static func currentLevel() -> MemoryVMPressureLevel? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return nil
        }
        return MemoryVMPressureLevel(rawValue: Int(level))
    }
}
