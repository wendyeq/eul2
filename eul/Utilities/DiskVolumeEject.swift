//
//  DiskVolumeEject.swift
//  eul
//
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import AppKit
import Foundation

enum DiskVolumeEject {
    static func unmountAndEject(path: String) throws {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try NSWorkspace.shared.unmountAndEjectDevice(at: url)
    }
}
