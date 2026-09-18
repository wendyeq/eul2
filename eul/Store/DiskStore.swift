//
//  DiskStore.swift
//  eul
//
//  Created by Gao Sun on 2020/11/1.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Combine
import Foundation
import SharedLibrary
import SwiftUI

class DiskStore: ObservableObject, Refreshable {
    private var activeCancellable: AnyCancellable?
    private var lastIOByContainer = [String: (read: UInt64, write: UInt64)]()
    private var lastIOTimestamp = Date().timeIntervalSince1970

    @ObservedObject var componentsStore = SharedStore.components
    @ObservedObject var menuComponentsStore = SharedStore.menuComponents
    var config: EulComponentConfig {
        SharedStore.componentConfig[EulComponent.Disk]
    }

    @Published var list: DiskList?
    @Published var ssdTemperature: Double?

    var selectedDisk: DiskList.Disk? {
        guard config.diskSelection != "" else {
            return nil
        }
        return list?.disks.filter { $0.name == config.diskSelection }.first
    }

    var ceilingBytes: UInt64? {
        selectedDisk?.size ?? list?.disks.reduce(0) { $0 + $1.size }
    }

    var freeBytes: UInt64? {
        selectedDisk?.freeSize ?? list?.disks.reduce(0) { $0 + $1.freeSize }
    }

    var usageString: String {
        guard let ceiling = ceilingBytes, let free = freeBytes else {
            return "N/A"
        }
        return ByteUnit(ceiling - free, kilo: 1000).readable
    }

    var usagePercentageString: String {
        guard let ceiling = ceilingBytes, let free = freeBytes else {
            return "N/A"
        }
        return (Double(ceiling - free) / Double(ceiling)).percentageString
    }

    var freeString: String {
        guard let free = freeBytes else {
            return "N/A"
        }
        return ByteUnit(free, kilo: 1000).readable
    }

    var totalString: String {
        guard let ceiling = ceilingBytes else {
            return "N/A"
        }
        return ByteUnit(ceiling, kilo: 1000).readable
    }

    @objc func refresh() {
        ssdTemperature = SmcControl.shared.ssdTemperature
        Print("DiskStore SSD", ssdTemperature as Any)

        guard
            componentsStore.activeComponents.contains(.Disk)
            || menuComponentsStore.activeComponents.contains(.Disk)
        else {
            return
        }

        guard let volumes = (try? FileManager.default.contentsOfDirectory(atPath: DiskList.volumesPath)) else {
            list = nil
            return
        }

        // Every APFS volume in a container reports the whole container's size and
        // free space, so one entry per mount point would multiply the totals.
        var containerOrder = [String]()
        var diskByContainer = [String: DiskList.Disk]()
        let sampleTime = Date().timeIntervalSince1970
        let sampleInterval = sampleTime - lastIOTimestamp
        var nextIOByContainer = lastIOByContainer

        for name in volumes.sorted() {
            if name.starts(with: ".") || name.contains("com.apple") { continue }

            let path = DiskList.pathForName(name)
            let url = URL(fileURLWithPath: path)

            guard
                let resourceValues = try? url.resourceValues(forKeys: [
                    .volumeIsLocalKey,
                    .volumeIsEjectableKey,
                    .volumeIsInternalKey,
                ]),
                resourceValues.volumeIsLocal == true,
                let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path),
                let size = attributes[FileAttributeKey.systemSize] as? UInt64,
                let freeSize = attributes[FileAttributeKey.systemFreeSize] as? UInt64,
                let container = Self.containerIdentifier(for: path)
            else {
                continue
            }

            let isEjectable = resourceValues.volumeIsEjectable
                ?? !(resourceValues.volumeIsInternal ?? false)
            let disk = DiskList.Disk(
                name: name,
                size: size,
                freeSize: freeSize,
                isEjectable: isEjectable,
                containerID: container,
                readSpeedInByte: 0,
                writeSpeedInByte: 0
            )

            if diskByContainer[container] == nil {
                containerOrder.append(container)
                diskByContainer[container] = disk
            } else if Self.isBootVolume(path) {
                // Name the container after the boot volume rather than whichever
                // sibling (Recovery, Preboot, …) happened to sort first.
                diskByContainer[container] = disk
            }
        }

        let disks = containerOrder.compactMap { container -> DiskList.Disk? in
            guard let disk = diskByContainer[container] else {
                return nil
            }

            var readSpeed = 0.0
            var writeSpeed = 0.0
            if
                let bsdName = Self.bsdName(for: disk.path),
                let sample = DiskBlockIO.cumulativeBytes(bsdName: bsdName)
            {
                if let previous = lastIOByContainer[container], sampleInterval > 0 {
                    if sample.read >= previous.read {
                        readSpeed = Double(sample.read - previous.read) / sampleInterval
                    }
                    if sample.write >= previous.write {
                        writeSpeed = Double(sample.write - previous.write) / sampleInterval
                    }
                }
                nextIOByContainer[container] = (sample.read, sample.write)
            }

            return DiskList.Disk(
                name: disk.name,
                size: disk.size,
                freeSize: disk.freeSize,
                isEjectable: disk.isEjectable,
                containerID: disk.containerID,
                readSpeedInByte: readSpeed,
                writeSpeedInByte: writeSpeed
            )
        }

        let activeContainers = Set(containerOrder)
        lastIOByContainer = nextIOByContainer.filter { activeContainers.contains($0.key) }
        if sampleInterval > 0 {
            lastIOTimestamp = sampleTime
        }

        list = DiskList(disks: disks)

        Print(
            "💽 disks",
            list?.disks.map { "\($0.name) container-total=\(ByteUnit($0.size, kilo: 1000).readable)" } as Any,
            "aggregate total",
            totalString,
            "free",
            freeString
        )
    }

    private static func bsdName(for path: String) -> String? {
        guard let device = mountDevice(for: path) else {
            return nil
        }
        let prefix = "/dev/"
        guard device.hasPrefix(prefix) else {
            return nil
        }
        return String(device.dropFirst(prefix.count))
    }

    private static func mountDevice(for path: String) -> String? {
        var info = statfs()
        guard statfs(path, &info) == 0 else {
            return nil
        }

        var mountFrom = info.f_mntfromname
        let length = MemoryLayout.size(ofValue: mountFrom)
        return withUnsafePointer(to: &mountFrom) {
            $0.withMemoryRebound(to: CChar.self, capacity: length) {
                String(cString: $0)
            }
        }
    }

    /// `/dev/disk3s1s1` and `/dev/disk3s3` are separate volumes sharing container
    /// `disk3`. Sources outside `/dev` stay distinct under their own name.
    private static func containerIdentifier(for path: String) -> String? {
        var info = statfs()
        guard statfs(path, &info) == 0 else {
            return nil
        }

        guard let device = mountDevice(for: path) else {
            return nil
        }

        let prefix = "/dev/disk"
        guard device.hasPrefix(prefix) else {
            return device
        }
        return "disk" + device.dropFirst(prefix.count).prefix { $0.isNumber }
    }

    /// `/Volumes/Macintosh HD` is a symlink to `/`.
    private static func isBootVolume(_ path: String) -> Bool {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path == "/"
    }

    init() {
        initObserver(for: .StoreShouldRefresh)
        // refresh immediately to prevent "N/A"
        activeCancellable = Publishers
            .CombineLatest(componentsStore.$activeComponents, menuComponentsStore.$activeComponents)
            .sink { _ in
                DispatchQueue.main.async {
                    self.refresh()
                }
            }
    }
}
