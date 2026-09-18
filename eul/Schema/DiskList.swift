//
//  DiskList.swift
//  eul
//
//  Created by Gao Sun on 2020/11/1.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Foundation
import SharedLibrary

struct DiskList {
    static let volumesPath = "/Volumes"
    static func pathForName(_ name: String) -> String {
        volumesPath + "/" + name
    }

    struct Disk: Identifiable {
        let name: String
        let size: UInt64
        let freeSize: UInt64
        let isEjectable: Bool
        let containerID: String
        let readSpeedInByte: Double
        let writeSpeedInByte: Double

        var id: String {
            containerID
        }

        var readSpeedString: String {
            ByteUnit(readSpeedInByte).readable + "/s"
        }

        var writeSpeedString: String {
            ByteUnit(writeSpeedInByte).readable + "/s"
        }

        var sizeString: String {
            return ByteUnit(size, kilo: 1000).readable
        }

        var freeSizeString: String {
            return ByteUnit(freeSize, kilo: 1000).readable
        }

        var usedSizeString: String {
            return ByteUnit(size - freeSize, kilo: 1000).readable
        }

        var path: String {
            pathForName(name)
        }
    }

    let disks: [Disk]
}
