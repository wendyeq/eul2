//
//  TopStore.swift
//  eul
//
//  Created by Jevon Mao on 1/22/21.
//  Copyright © 2021 Gao Sun. All rights reserved.
//

import Combine
import Darwin
import SwiftUI
import SystemKit

// TO-DO: extract store logic

// MARK: Instance

class TopStore: ObservableObject {
    private var memorySizeMB = System.physicalMemory() * 1000
    private var cpuTimer: Timer?
    private var ramTimer: Timer?
    private var cpuActiveCancellable: AnyCancellable?
    private var ramActiveCancellable: AnyCancellable?
    private var processPinCancellable: AnyCancellable?
    private var ramHasBaseline = false
    private var lastCpuTimes: [Int: UInt64] = [:]
    private var lastCpuTimestamp: TimeInterval?
    private let sampleQueue = DispatchQueue(label: "eul.top-store")

    @ObservedObject var preferenceStore = SharedStore.preference
    @Published var cpuDataAvailable = false
    @Published var ramDataAvailable = false
    @Published var cpuTopProcesses: [ProcessCpuUsage] = []
    @Published var ramTopProcesses: [RamUsage] = []

    func updateRAM(shouldStart: Bool) {
        guard shouldStart else {
            ramTimer?.invalidate()
            ramTimer = nil
            return
        }

        if ramTimer != nil {
            Print("ram task already started")
            return
        }

        ramDataAvailable = false
        ramTopProcesses = []
        sampleQueue.async { [self] in
            ramHasBaseline = false
        }

        sampleRAM()
        let timer = Timer.scheduledTimer(withTimeInterval: Double(preferenceStore.smcRefreshRate), repeats: true) { [self] _ in
            sampleRAM()
        }
        RunLoop.main.add(timer, forMode: .common)
        ramTimer = timer
    }

    func updateCPU(shouldStart: Bool) {
        guard shouldStart else {
            cpuTimer?.invalidate()
            cpuTimer = nil
            return
        }

        if cpuTimer != nil {
            Print("cpu task already started")
            return
        }

        cpuDataAvailable = false
        cpuTopProcesses = []
        sampleQueue.async { [self] in
            lastCpuTimes.removeAll()
            lastCpuTimestamp = nil
        }

        sampleCPU()
        let timer = Timer.scheduledTimer(withTimeInterval: Double(preferenceStore.smcRefreshRate), repeats: true) { [self] _ in
            sampleCPU()
        }
        RunLoop.main.add(timer, forMode: .common)
        cpuTimer = timer
    }

    init() {
        cpuActiveCancellable = Publishers
            .CombineLatest3(
                preferenceStore.$showCPUTopActivities,
                SharedStore.menuComponents.$activeComponents,
                SharedStore.ui.$menuOpened
            )
            .map {
                $0 && $1.contains(.CPU) && $2
            }
            .sink { [self] in
                updateCPU(shouldStart: $0)
            }

        ramActiveCancellable = Publishers
            .CombineLatest3(
                preferenceStore.$showRAMTopActivities,
                SharedStore.menuComponents.$activeComponents,
                SharedStore.ui.$menuOpened
            )
            .map {
                $0 && $1.contains(.Memory) && $2
            }
            .sink { [self] in
                updateRAM(shouldStart: $0)
            }

        processPinCancellable = SharedStore.ui.$pinnedMenuProcessPIDBySection
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [self] _ in
                refreshMenuProcessPinOrdering()
            }
    }

    func refreshMenuProcessPinOrdering() {
        cpuTopProcesses = ProcessMenuListPin.mergePinnedFirst(
            ranked: cpuTopProcesses,
            section: ProcessMenuListPin.cpuSection,
            limit: 5
        )
        ramTopProcesses = ProcessMenuListPin.mergePinnedFirst(
            ranked: ramTopProcesses,
            section: ProcessMenuListPin.memorySection,
            limit: 5
        )
    }
}

// MARK: Private Methods

extension TopStore {
    private struct TaskSample {
        let pid: Int
        let cpuTime: UInt64
        let residentBytes: UInt64
    }

    private func sampleCPU() {
        sampleQueue.async { [self] in
            let samples = listTaskSamples()
            let now = Date().timeIntervalSince1970
            var nextTimes: [Int: UInt64] = [:]
            nextTimes.reserveCapacity(samples.count)
            for sample in samples {
                nextTimes[sample.pid] = sample.cpuTime
            }

            let previousTimes = lastCpuTimes
            let previousTimestamp = lastCpuTimestamp
            lastCpuTimes = nextTimes
            lastCpuTimestamp = now

            guard let previousTimestamp = previousTimestamp else {
                DispatchQueue.main.async { [self] in
                    guard cpuTimer != nil else { return }
                    cpuTopProcesses = []
                    cpuDataAvailable = false
                }
                return
            }

            let elapsed = now - previousTimestamp
            guard elapsed > 0 else { return }

            let runningApps = NSWorkspace.shared.runningApplications
            let result = samples.compactMap { sample -> (pid: Int, value: Double)? in
                guard let previous = previousTimes[sample.pid], sample.cpuTime >= previous else {
                    return nil
                }

                let cpu = (Double(sample.cpuTime - previous) / 1_000_000_000) / elapsed * 100
                guard cpu.isFinite, cpu >= 0.1 else {
                    return nil
                }

                return (sample.pid, cpu)
            }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { sample in
                ProcessCpuUsage(
                    pid: sample.pid,
                    command: Info.getProcessCommand(pid: sample.pid) ?? "",
                    value: sample.value,
                    runningApp: runningApps.first(where: { $0.processIdentifier == sample.pid })
                )
            }

            Print("CPU top is updating")
            DispatchQueue.main.async { [self] in
                guard cpuTimer != nil else { return }
                cpuTopProcesses = ProcessMenuListPin.mergePinnedFirst(
                    ranked: result,
                    section: ProcessMenuListPin.cpuSection,
                    limit: 5,
                    fallback: { pid in
                        guard let sample = samples.first(where: { $0.pid == pid }),
                              let previous = previousTimes[sample.pid],
                              sample.cpuTime >= previous
                        else {
                            return nil
                        }
                        let cpu = (Double(sample.cpuTime - previous) / 1_000_000_000) / elapsed * 100
                        guard cpu.isFinite else {
                            return nil
                        }
                        return ProcessCpuUsage(
                            pid: sample.pid,
                            command: Info.getProcessCommand(pid: sample.pid) ?? "",
                            value: cpu,
                            runningApp: runningApps.first(where: { $0.processIdentifier == sample.pid })
                        )
                    }
                )
                cpuDataAvailable = true
            }
        }
    }

    private func sampleRAM() {
        sampleQueue.async { [self] in
            let samples = listTaskSamples()

            guard ramHasBaseline else {
                ramHasBaseline = true
                DispatchQueue.main.async { [self] in
                    guard ramTimer != nil else { return }
                    ramTopProcesses = []
                    ramDataAvailable = false
                }
                return
            }

            let runningApps = NSWorkspace.shared.runningApplications
            let result = samples
                .sorted { $0.residentBytes > $1.residentBytes }
                .prefix(5)
                .map { sample in
                    let ram = Double(sample.residentBytes) / (1024.0 * 1024.0)
                    return RamUsage(
                        pid: sample.pid,
                        command: Info.getProcessCommand(pid: sample.pid) ?? "",
                        value: 100 * (ram / memorySizeMB),
                        usageAmount: ram,
                        runningApp: runningApps.first(where: { $0.processIdentifier == sample.pid })
                    )
                }

            DispatchQueue.main.async { [self] in
                guard ramTimer != nil else { return }
                ramTopProcesses = ProcessMenuListPin.mergePinnedFirst(
                    ranked: result,
                    section: ProcessMenuListPin.memorySection,
                    limit: 5,
                    fallback: { pid in
                        guard let sample = samples.first(where: { $0.pid == pid }) else {
                            return nil
                        }
                        let ram = Double(sample.residentBytes) / (1024.0 * 1024.0)
                        return RamUsage(
                            pid: sample.pid,
                            command: Info.getProcessCommand(pid: sample.pid) ?? "",
                            value: 100 * (ram / memorySizeMB),
                            usageAmount: ram,
                            runningApp: runningApps.first(where: { $0.processIdentifier == sample.pid })
                        )
                    }
                )
                ramDataAvailable = true
            }
        }
    }

    private func listTaskSamples() -> [TaskSample] {
        let bytesNeeded = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytesNeeded > 0 else {
            return []
        }

        let stride = MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: Int(bytesNeeded) / stride + 16)
        let bytesUsed = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count * stride))
        }
        guard bytesUsed > 0 else {
            return []
        }

        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        return pids.prefix(Int(bytesUsed) / stride).compactMap { pid in
            guard pid > 0 else {
                return nil
            }
            var info = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else {
                return nil
            }
            return TaskSample(
                pid: Int(pid),
                cpuTime: info.pti_total_user &+ info.pti_total_system,
                residentBytes: info.pti_resident_size
            )
        }
    }
}
