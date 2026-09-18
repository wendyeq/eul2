//
//  DiskBlockIO.swift
//  eul
//
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Foundation
import IOKit
import IOKit.storage

enum DiskBlockIO {
    struct ByteCounters {
        let read: UInt64
        let write: UInt64
    }

    static func cumulativeBytes(bsdName: String) -> ByteCounters? {
        guard let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else {
            return nil
        }
        let media = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard media != 0 else {
            return nil
        }
        defer { IOObjectRelease(media) }

        guard let driver = blockStorageDriver(startingAt: media) else {
            return nil
        }
        defer { IOObjectRelease(driver) }

        guard
            let properties = IOHelper.getProperties(entry: driver),
            let statistics = properties["Statistics"] as? [String: Any]
        else {
            return nil
        }

        let read = (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
        let write = (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        return ByteCounters(read: read, write: write)
    }

    private static func blockStorageDriver(startingAt entry: io_object_t) -> io_object_t? {
        var current = entry
        while current != 0 {
            if IOObjectConformsTo(current, kIOBlockStorageDriverClass) != 0 {
                IOObjectRetain(current)
                return current
            }

            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else {
                break
            }
            if current != entry {
                IOObjectRelease(current)
            }
            current = parent
        }

        if current != entry, current != 0 {
            IOObjectRelease(current)
        }
        return nil
    }
}
