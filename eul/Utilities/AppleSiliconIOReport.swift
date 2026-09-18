//
//  AppleSiliconIOReport.swift
//  eul
//

import Darwin
import Darwin.Mach
import Foundation
import IOKit
import Localize_Swift

struct AppleSiliconClusterMetrics {
    var usageEPercent: Double?
    var usagePPercent: Double?
    var freqEMhz: Double?
    var freqPMhz: Double?
    var pPeakMhz: Double?
    var throttleLabel: String?
}

final class AppleSiliconIOReport {
    static let shared = AppleSiliconIOReport()

    private(set) var isReady = false
    private(set) var lastCluster = AppleSiliconClusterMetrics()
    private(set) var lastANEActive: Bool?
    private(set) var lastBandwidthGBs: Int?

    private typealias SubscriptionRef = OpaquePointer

    private var copyChannelsInGroup: (@convention(c) (CFString, CFString?, UInt64, UInt64, UInt64) -> CFMutableDictionary?)?
    private var mergeChannels: (@convention(c) (CFMutableDictionary, CFMutableDictionary, CFTypeRef?) -> Void)?
    private var createSubscription: (@convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary, UnsafeMutablePointer<CFMutableDictionary?>?, UInt64, CFTypeRef?) -> SubscriptionRef?)?
    private var createSamples: (@convention(c) (SubscriptionRef?, CFMutableDictionary?, CFTypeRef?) -> CFDictionary?)?
    private var createSamplesDelta: (@convention(c) (CFDictionary?, CFDictionary?, CFTypeRef?) -> CFDictionary?)?
    private var iterate: (@convention(c) (CFDictionary?, @escaping (CFDictionary) -> Int32) -> Void)?
    private var channelGroup: (@convention(c) (CFDictionary) -> CFString?)?
    private var channelSubGroup: (@convention(c) (CFDictionary) -> CFString?)?
    private var channelName: (@convention(c) (CFDictionary) -> CFString?)?
    private var stateCount: (@convention(c) (CFDictionary) -> Int32)?
    private var stateName: (@convention(c) (CFDictionary, Int32) -> CFString?)?
    private var stateResidency: (@convention(c) (CFDictionary, Int32) -> Int64)?

    private var subscription: SubscriptionRef?
    private var subscribedChannels: CFMutableDictionary?
    private var previousSample: CFDictionary?

    private var eCoreIndices = [Int]()
    private var pCoreIndices = [Int]()
    private var eFreqTable = [Double]()
    private var pFreqTable = [Double]()
    private var pPeakMhz: Double = 0

    private struct TickSample {
        var busy: UInt64
        var total: UInt64
    }

    private var previousTicks = [TickSample]()

    private init() {}

    func startIfNeeded() {
        guard !isReady else { return }
        guard loadSymbols(), subscribe() else { return }
        cacheCoreLayout()
        cacheDVFSTables()
        isReady = true
    }

    func refreshIfNeeded() {
        startIfNeeded()
        guard
            isReady,
            let subscription = subscription,
            let subscribedChannels = subscribedChannels,
            let createSamples = createSamples,
            let createSamplesDelta = createSamplesDelta,
            let iterate = iterate
        else {
            lastCluster = AppleSiliconClusterMetrics()
            lastANEActive = nil
            lastBandwidthGBs = nil
            return
        }

        guard let sample = createSamples(subscription, subscribedChannels, nil) else {
            return
        }

        defer {
            previousSample = sample
        }

        guard let previousSample = previousSample else {
            return
        }

        guard let delta = createSamplesDelta(previousSample, sample, nil) else {
            return
        }
        var cluster = clusterUsageFromTicks()
        cluster = mergeClusterFrequencies(into: cluster, delta: delta, iterate: iterate)
        lastCluster = cluster
        lastANEActive = aneMetrics(from: delta, iterate: iterate)
        lastBandwidthGBs = bandwidthMetrics(from: delta, iterate: iterate)
    }

    // MARK: - Setup

    private func loadSymbols() -> Bool {
        guard let handle = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY) else {
            return false
        }

        func load<T>(_ name: String) -> T? {
            guard let symbol = dlsym(handle, name) else { return nil }
            return unsafeBitCast(symbol, to: T.self)
        }

        copyChannelsInGroup = load("IOReportCopyChannelsInGroup")
        mergeChannels = load("IOReportMergeChannels")
        createSubscription = load("IOReportCreateSubscription")
        createSamples = load("IOReportCreateSamples")
        createSamplesDelta = load("IOReportCreateSamplesDelta")
        iterate = load("IOReportIterate")
        channelGroup = load("IOReportChannelGetGroup")
        channelSubGroup = load("IOReportChannelGetSubGroup")
        channelName = load("IOReportChannelGetChannelName")
        stateCount = load("IOReportStateGetCount")
        stateName = load("IOReportStateGetNameForIndex")
        stateResidency = load("IOReportStateGetResidency")

        return copyChannelsInGroup != nil
            && mergeChannels != nil
            && createSubscription != nil
            && createSamples != nil
            && createSamplesDelta != nil
            && iterate != nil
            && channelGroup != nil
            && channelSubGroup != nil
            && channelName != nil
            && stateCount != nil
            && stateName != nil
            && stateResidency != nil
    }

    private func subscribe() -> Bool {
        guard let copyChannelsInGroup = copyChannelsInGroup,
              let mergeChannels = mergeChannels,
              let createSubscription = createSubscription
        else {
            return false
        }

        let groups: [(String, String?)] = [
            ("CPU Stats", "CPU Core Performance States"),
            ("ANE", "IOP State"),
            ("PMP", "DCS BW"),
        ]

        var merged: CFMutableDictionary?
        for (group, sub) in groups {
            let subCF = sub.map { $0 as CFString }
            guard let channels = copyChannelsInGroup(group as CFString, subCF, 0, 0, 0) else {
                continue
            }
            if merged == nil {
                merged = channels
            } else {
                mergeChannels(merged!, channels, nil)
            }
        }

        guard let channelSet = merged else { return false }

        var subscribed: CFMutableDictionary?
        guard let subscription = createSubscription(nil, channelSet, &subscribed, 0, nil),
              let subscribed
        else {
            return false
        }

        self.subscription = subscription
        subscribedChannels = subscribed
        return true
    }

    private func cacheCoreLayout() {
        eCoreIndices = []
        pCoreIndices = []

        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        if cpus != 0 {
            defer { IOObjectRelease(cpus) }
            var iterator = io_iterator_t()
            if IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &iterator) == KERN_SUCCESS {
                defer { IOObjectRelease(iterator) }
                var child = IOIteratorNext(iterator)
                while child != 0 {
                    if let properties = IOHelper.getProperties(entry: child) {
                        let cluster = Self.registryString(properties["cluster-type"])
                        if let logicalId = Self.registryInt(properties["logical-cpu-id"]), let cluster {
                            if cluster.hasPrefix("E") {
                                eCoreIndices.append(logicalId)
                            } else if cluster.hasPrefix("P") {
                                pCoreIndices.append(logicalId)
                            }
                        }
                    }
                    IOObjectRelease(child)
                    child = IOIteratorNext(iterator)
                }
            }
        }

        eCoreIndices.sort()
        pCoreIndices.sort()
        Print("IOReport cluster-type E", eCoreIndices, "P", pCoreIndices)
    }

    private static func registryString(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespaces))
            return trimmed.isEmpty ? nil : trimmed
        }
        if let data = value as? Data, let string = String(data: data, encoding: .utf8) {
            let trimmed = string.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespaces))
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func registryInt(_ value: Any?) -> Int? {
        if let number = value as? Int {
            return number
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let data = value as? Data, data.count >= 4 {
            return Int(data.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self) })
        }
        return nil
    }

    private func cacheDVFSTables() {
        eFreqTable = readDVFSTable(property: "voltage-states1-sram")
        pFreqTable = readDVFSTable(property: "voltage-states5-sram")
        pPeakMhz = pFreqTable.max() ?? 0
    }

    private func readDVFSTable(property: String) -> [Double] {
        let path = "IODeviceTree:/arm-io/pmgr"
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, path)
        guard entry != 0 else { return [] }
        defer { IOObjectRelease(entry) }

        guard
            let data = IORegistryEntryCreateCFProperty(
                entry,
                property as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? Data,
            data.count >= 8
        else {
            return []
        }

        var mhz = [Double]()
        for offset in stride(from: 0, to: data.count - 7, by: 8) {
            let raw = data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.load(as: UInt32.self) }
            if raw == 0 { continue }
            let freqMhz = raw > 100_000_000 ? Double(raw) / 1_000_000 : Double(raw) / 1000
            mhz.append(freqMhz)
        }
        return mhz
    }

    // MARK: - CPU ticks

    private func clusterUsageFromTicks() -> AppleSiliconClusterMetrics {
        var metrics = AppleSiliconClusterMetrics()
        guard !eCoreIndices.isEmpty else { return metrics }

        let sample = sampleProcessorTicks()
        let maxIndex = (eCoreIndices + pCoreIndices).max() ?? -1
        guard sample.count > maxIndex else { return metrics }

        if previousTicks.count == sample.count {
            var eBusy: UInt64 = 0
            var eTotal: UInt64 = 0
            var pBusy: UInt64 = 0
            var pTotal: UInt64 = 0

            for index in 0..<sample.count {
                let busyDelta = sample[index].busy &- previousTicks[index].busy
                let totalDelta = sample[index].total &- previousTicks[index].total
                if eCoreIndices.contains(index) {
                    eBusy &+= busyDelta
                    eTotal &+= totalDelta
                } else if pCoreIndices.contains(index) {
                    pBusy &+= busyDelta
                    pTotal &+= totalDelta
                }
            }

            if eTotal > 0 {
                metrics.usageEPercent = Double(eBusy) / Double(eTotal) * 100
            }
            if pTotal > 0 {
                metrics.usagePPercent = Double(pBusy) / Double(pTotal) * 100
            }
        }

        previousTicks = sample
        return metrics
    }

    private func sampleProcessorTicks() -> [TickSample] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let host = mach_host_self()
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info = info
        else {
            return []
        }

        defer {
            let deallocateSize = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), deallocateSize)
        }

        let loadInfo = info.withMemoryRebound(to: processor_cpu_load_info.self, capacity: Int(cpuCount)) { $0 }
        var samples = [TickSample]()
        samples.reserveCapacity(Int(cpuCount))

        for index in 0..<Int(cpuCount) {
            let cpuTicks = loadInfo[index].cpu_ticks
            var states = [UInt64](repeating: 0, count: Int(CPU_STATE_MAX))
            withUnsafeBytes(of: cpuTicks) { raw in
                let count = min(Int(CPU_STATE_MAX), raw.count / MemoryLayout<UInt32>.stride)
                for state in 0..<count {
                    states[state] = UInt64(raw.load(fromByteOffset: state * MemoryLayout<UInt32>.stride, as: UInt32.self))
                }
            }
            let user = states[Int(CPU_STATE_USER)]
            let system = states[Int(CPU_STATE_SYSTEM)]
            let idle = states[Int(CPU_STATE_IDLE)]
            let nice = states[Int(CPU_STATE_NICE)]
            let busy = user &+ system &+ nice
            let total = busy &+ idle
            samples.append(TickSample(busy: busy, total: total))
        }
        return samples
    }

    // MARK: - Frequencies

    private func mergeClusterFrequencies(
        into metrics: AppleSiliconClusterMetrics,
        delta: CFDictionary,
        iterate: @escaping (CFDictionary?, @escaping (CFDictionary) -> Int32) -> Void
    ) -> AppleSiliconClusterMetrics {
        var result = metrics
        var eWeighted = 0.0
        var eWeight = 0.0
        var pWeighted = 0.0
        var pWeight = 0.0

        iterate(delta) { channel in
            guard
                let channelGroup = self.channelGroup?(channel) as String?,
                channelGroup == "CPU Stats",
                let name = self.channelName?(channel) as String?
            else {
                return 0
            }

            let isE = name.hasPrefix("ECPU")
            let isP = name.hasPrefix("PCPU")
            guard isE || isP else { return 0 }

            let table = isE ? self.eFreqTable : self.pFreqTable
            guard !table.isEmpty, let stateCount = self.stateCount?(channel) else { return 0 }

            var freqIndex = 0
            for stateIndex in 0..<stateCount {
                guard
                    let stateLabel = self.stateName?(channel, stateIndex) as String?,
                    let residency = self.stateResidency?(channel, stateIndex)
                else {
                    continue
                }
                let weight = Double(residency)
                if weight <= 0 { continue }
                if stateLabel == "IDLE" || stateLabel == "OFF" || stateLabel == "DOWN" {
                    continue
                }
                if freqIndex < table.count {
                    let mhz = table[freqIndex]
                    if isE {
                        eWeighted += weight * mhz
                        eWeight += weight
                    } else {
                        pWeighted += weight * mhz
                        pWeight += weight
                    }
                }
                freqIndex += 1
            }
            return 0
        }

        if eWeight > 0 { result.freqEMhz = eWeighted / eWeight }
        if pWeight > 0 { result.freqPMhz = pWeighted / pWeight }
        result.pPeakMhz = pPeakMhz

        if let usageP = result.usagePPercent,
           let freqP = result.freqPMhz,
           pPeakMhz > 0,
           usageP > 25,
           freqP < pPeakMhz * 0.92
        {
            let ratio = freqP / pPeakMhz
            result.throttleLabel = AppleSiliconIOReport.formatThrottle(ratio: ratio)
        }

        return result
    }

    static func formatThrottle(ratio: Double) -> String {
        let percent = Int((ratio * 100).rounded())
        return String(format: "cpu.throttle.value".localized(), percent)
    }

    static func formatFrequency(mhz: Double) -> String {
        if mhz >= 1000 {
            return String(format: "%.1f GHz", mhz / 1000)
        }
        return String(format: "%.0f MHz", mhz)
    }

    // MARK: - ANE

    private func aneMetrics(
        from delta: CFDictionary,
        iterate: @escaping (CFDictionary?, @escaping (CFDictionary) -> Int32) -> Void
    ) -> Bool? {
        var running = 0.0
        var total = 0.0
        var found = false

        iterate(delta) { channel in
            guard
                let group = self.channelGroup?(channel) as String?,
                group == "ANE",
                let sub = self.channelSubGroup?(channel) as String?,
                sub == "IOP State",
                let name = self.channelName?(channel) as String?,
                name == "status",
                let stateCount = self.stateCount?(channel)
            else {
                return 0
            }
            found = true
            for stateIndex in 0..<stateCount {
                guard
                    let label = self.stateName?(channel, stateIndex) as String?,
                    let residency = self.stateResidency?(channel, stateIndex)
                else {
                    continue
                }
                let weight = Double(residency)
                total += weight
                if label == "Running" {
                    running += weight
                }
            }
            return 0
        }

        guard found, total > 0 else { return nil }
        return running > 0
    }

    // MARK: - Bandwidth

    private func bandwidthMetrics(
        from delta: CFDictionary,
        iterate: @escaping (CFDictionary?, @escaping (CFDictionary) -> Int32) -> Void
    ) -> Int? {
        var weightedSum = 0.0
        var totalWeight = 0.0
        var found = false

        iterate(delta) { channel in
            guard
                let group = self.channelGroup?(channel) as String?,
                group == "PMP",
                let sub = self.channelSubGroup?(channel) as String?,
                sub == "DCS BW",
                let name = self.channelName?(channel) as String?,
                name == "RD+WR",
                let stateCount = self.stateCount?(channel)
            else {
                return 0
            }
            found = true
            for stateIndex in 0..<stateCount {
                guard
                    let bucketLabel = self.stateName?(channel, stateIndex) as String?,
                    let residency = self.stateResidency?(channel, stateIndex)
                else {
                    continue
                }
                let trimmed = bucketLabel.trimmingCharacters(in: .whitespaces)
                let gbs = Double(trimmed.prefix(while: { $0.isNumber || $0 == "." })) ?? 0
                let weight = Double(residency)
                weightedSum += weight * gbs
                totalWeight += weight
            }
            return 0
        }

        guard found, totalWeight > 0 else { return nil }
        let average = weightedSum / totalWeight
        guard average > 0, average < 200 else { return nil }
        return Int(average.rounded())
    }
}
