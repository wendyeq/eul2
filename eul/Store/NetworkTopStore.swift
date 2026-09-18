//
//  NetworkTopStore.swift
//  eul
//
//  Created by Gao Sun on 2020/10/17.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import AppKit
import Combine
import Darwin
import SwiftUI

class NetworkTopStore: ObservableObject {
    struct NetworkSpeed: CustomStringConvertible {
        var inSpeedInByte: Double = 0
        var outSpeedInByte: Double = 0

        var totalSpeedInByte: Double {
            inSpeedInByte + outSpeedInByte
        }

        var description: String {
            fatalError("not implemented")
        }
    }

    struct ProcessNetworkUsage: ProcessUsage {
        typealias T = NetworkSpeed
        let pid: Int
        let command: String
        let value: NetworkSpeed
        let runningApp: NSRunningApplication?
    }

    private var timer: Timer?
    private var activeCancellable: AnyCancellable?
    private var processPinCancellable: AnyCancellable?
    private var lastTimestamp: TimeInterval = Date().timeIntervalSince1970
    private var lastInBytes: [Int: Double] = [:]
    private var lastOutBytes: [Int: Double] = [:]
    private var session: NstatSession?
    private let sampleQueue = DispatchQueue(label: "eul.network-top")

    @ObservedObject var preferenceStore = SharedStore.preference
    @Published var processes: [ProcessNetworkUsage] = []

    private var interval: Int {
        preferenceStore.networkRefreshRate
    }

    var totalSpeed: NetworkSpeed {
        processes.reduce(into: NetworkSpeed()) { result, usage in
            result.inSpeedInByte += usage.value.inSpeedInByte
            result.outSpeedInByte += usage.value.outSpeedInByte
        }
    }

    private func run() {
        sampleQueue.async { [self] in
            guard let session = session else {
                return
            }

            guard let totals = session.poll() else {
                print("unable to fetch network activity, please make sure network statistics are available")
                return
            }

            let runningApps = NSWorkspace.shared.runningApplications
            let time = Date().timeIntervalSince1970
            let timeElapsed = time - lastTimestamp
            lastTimestamp = time

            Print("network top is updating")
            let result = totals.compactMap { pid, bytes -> ProcessNetworkUsage? in
                let lastIn = lastInBytes[pid]
                let lastOut = lastOutBytes[pid]
                lastInBytes[pid] = bytes.inBytes
                lastOutBytes[pid] = bytes.outBytes

                if lastIn == nil, lastOut == nil {
                    return nil
                }

                let speed = NetworkSpeed(
                    inSpeedInByte: lastIn.map { $0 > bytes.inBytes ? 0 : (bytes.inBytes - $0) / timeElapsed } ?? 0,
                    outSpeedInByte: lastOut.map { $0 > bytes.outBytes ? 0 : (bytes.outBytes - $0) / timeElapsed } ?? 0
                )

                guard speed.totalSpeedInByte >= 100 else {
                    return nil
                }

                return ProcessNetworkUsage(
                    pid: pid,
                    command: Info.getProcessCommand(pid: pid) ?? "",
                    value: speed,
                    runningApp: runningApps.first(where: { $0.processIdentifier == pid })
                )
            }
            .sorted(by: { $0.value.totalSpeedInByte > $1.value.totalSpeedInByte })

            DispatchQueue.main.async { [self] in
                guard timer != nil else { return }
                let previous = processes
                processes = ProcessMenuListPin.mergePinnedFirst(
                    ranked: result,
                    section: ProcessMenuListPin.networkSection,
                    limit: 3,
                    fallback: { pid in
                        result.first(where: { $0.pid == pid })
                            ?? previous.first(where: { $0.pid == pid })
                    }
                )
            }
        }
    }

    func update(shouldStart: Bool) {
        guard shouldStart else {
            timer?.invalidate()
            timer = nil
            sampleQueue.async { [self] in
                session = nil
            }
            return
        }

        if timer != nil {
            Print("network task already started")
            return
        }

        processes = []
        sampleQueue.async { [self] in
            lastInBytes.removeAll()
            lastOutBytes.removeAll()
            lastTimestamp = Date().timeIntervalSince1970
            session = NstatSession()
        }

        let timer = Timer.scheduledTimer(withTimeInterval: Double(interval), repeats: true) { _ in
            self.run()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    init() {
        activeCancellable = Publishers
            .CombineLatest3(
                preferenceStore.$showNetworkTopActivities,
                SharedStore.menuComponents.$activeComponents,
                SharedStore.ui.$menuOpened
            )
            .map {
                $0 && $1.contains(.Network) && $2
            }
            .sink { [self] in
                update(shouldStart: $0)
            }

        processPinCancellable = SharedStore.ui.$pinnedMenuProcessPIDBySection
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [self] _ in
                processes = ProcessMenuListPin.mergePinnedFirst(
                    ranked: processes,
                    section: ProcessMenuListPin.networkSection,
                    limit: 3
                )
            }
    }
}

// MARK: - com.apple.network.statistics kernel control (nstat)

private final class NstatSession {
    private enum Message {
        static let success: UInt32 = 0
        static let error: UInt32 = 1
        static let addAllSources: UInt32 = 1002
        static let getUpdate: UInt32 = 1007
        static let sourceUpdate: UInt32 = 10006
        static let headerLength = 16
        static let flagSupportsAggregate: UInt16 = 1
        static let flagContinuation: UInt16 = 2
        static let flagClosing: UInt16 = 4
    }

    private static let controlName = "com.apple.network.statistics"
    private static let ioctlGetInfo: CUnsignedLong = 0xC064_4E03 // CTLIOCGINFO = _IOWR('N', 3, ctl_info)
    private static let sourceRefAll: UInt64 = .max
    private static let filterSuppressSourceAdded: UInt64 = 0x0010_0000
    private static let providersTCP: Set<UInt32> = [2, 3] // kernel, userland
    private static let providersUDP: Set<UInt32> = [4, 5]
    /// connect() resets the kernel-control socket to an 8 KiB receive buffer, and the kernel silently
    /// drops update messages that do not fit, so the buffer must be enlarged after connecting.
    private static let receiveBufferSize = Int32(4 * 1024 * 1024)
    private static let replyTimeoutMs: Int32 = 1000

    /// `nstat_msg_src_update`: hdr(16) srcref(8) event_flags(8) nstat_counts(112) provider(4) descriptor
    private static let rxBytesOffset = 40
    private static let txBytesOffset = 56
    private static let providerOffset = 144
    private static let descriptorOffset = 148
    private static let tcpUpdateLength = 512
    private static let tcpPidOffset = 148 + 120
    private static let udpUpdateLength = 432
    private static let udpPidOffset = 148 + 132

    private var fd: Int32 = -1
    private var receiveBuffer = [UInt8](repeating: 0, count: 65536)
    private var pollContext: UInt64 = 0x100
    private var retired: [Int: (inBytes: UInt64, outBytes: UInt64)] = [:]

    init?() {
        guard openSocket() else {
            return nil
        }
        for provider in NstatSession.providersTCP.union(NstatSession.providersUDP) {
            subscribe(provider: provider)
        }
    }

    deinit {
        if fd >= 0 {
            Darwin.close(fd)
        }
    }

    func poll() -> [Int: (inBytes: Double, outBytes: Double)]? {
        pollContext += 1
        let deadline = Date().addingTimeInterval(Double(NstatSession.replyTimeoutMs) / 1000)
        var live: [Int: (inBytes: UInt64, outBytes: UInt64)] = [:]
        var needsMore = true
        while needsMore {
            var request = [UInt8](repeating: 0, count: 24)
            writeHeader(&request, context: pollContext, type: Message.getUpdate, flags: Message.flagContinuation)
            writeU64(NstatSession.sourceRefAll, to: &request, at: 16)
            guard send(request), let replyFlags = receive(untilReplyTo: pollContext, deadline: deadline, live: &live) else {
                return nil
            }
            needsMore = replyFlags & Message.flagContinuation != 0
        }

        var totals: [Int: (inBytes: Double, outBytes: Double)] = [:]
        for (pid, bytes) in live {
            totals[pid] = (Double(bytes.inBytes), Double(bytes.outBytes))
        }
        for (pid, bytes) in retired {
            let current = totals[pid] ?? (0, 0)
            totals[pid] = (current.inBytes + Double(bytes.inBytes), current.outBytes + Double(bytes.outBytes))
        }
        return totals
    }

    private func openSocket() -> Bool {
        let socketFD = socket(PF_SYSTEM, SOCK_DGRAM, SYSPROTO_CONTROL)
        guard socketFD >= 0 else {
            return false
        }

        var info = ctl_info()
        withUnsafeMutableBytes(of: &info.ctl_name) { buffer in
            guard let base = buffer.baseAddress else { return }
            memset(base, 0, buffer.count)
            _ = NstatSession.controlName.withCString { name in
                strncpy(base.assumingMemoryBound(to: CChar.self), name, buffer.count - 1)
            }
        }
        guard ioctl(socketFD, NstatSession.ioctlGetInfo, &info) == 0 else {
            Darwin.close(socketFD)
            return false
        }

        var address = sockaddr_ctl()
        address.sc_len = u_char(MemoryLayout<sockaddr_ctl>.size)
        address.sc_family = u_char(AF_SYSTEM)
        address.ss_sysaddr = UInt16(AF_SYS_CONTROL)
        address.sc_id = info.ctl_id
        address.sc_unit = 0
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                connect(socketFD, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_ctl>.size))
            }
        }
        guard connected == 0 else {
            Darwin.close(socketFD)
            return false
        }

        var receiveSize = NstatSession.receiveBufferSize
        guard setsockopt(socketFD, SOL_SOCKET, SO_RCVBUF, &receiveSize, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            Darwin.close(socketFD)
            return false
        }

        fd = socketFD
        return true
    }

    /// `nstat_msg_add_all_srcs`: hdr(16) filter(8) events(8) provider(4) target_pid(4) target_uuid(16)
    private func subscribe(provider: UInt32) {
        var request = [UInt8](repeating: 0, count: 56)
        writeHeader(&request, context: UInt64(0x1000 + provider), type: Message.addAllSources)
        writeU64(NstatSession.filterSuppressSourceAdded, to: &request, at: 16)
        writeU32(provider, to: &request, at: 32)
        writeU32(UInt32(bitPattern: -1), to: &request, at: 36)
        _ = send(request)
    }

    private func send(_ bytes: [UInt8]) -> Bool {
        guard fd >= 0 else { return false }
        return bytes.withUnsafeBytes { buffer in
            Darwin.send(fd, buffer.baseAddress, buffer.count, 0) == buffer.count
        }
    }

    private func receive(untilReplyTo context: UInt64, deadline: Date, live: inout [Int: (inBytes: UInt64, outBytes: UInt64)]) -> UInt16? {
        while true {
            let remaining = Int32(deadline.timeIntervalSinceNow * 1000)
            guard remaining > 0 else { return nil }

            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            guard Darwin.poll(&descriptor, 1, remaining) > 0 else {
                if errno == EINTR { continue }
                return nil
            }

            let count = receiveBuffer.withUnsafeMutableBytes { buffer in
                Int(recv(fd, buffer.baseAddress, buffer.count, 0))
            }
            guard count > 0 else {
                if errno == EINTR { continue }
                return nil
            }

            var offset = 0
            while offset + Message.headerLength <= count {
                let declared = Int(readU16(offset + 12))
                let length = declared > 0 ? declared : count - offset
                guard length >= Message.headerLength, offset + length <= count else { break }

                let type = readU32(offset + 8)
                switch type {
                case Message.success, Message.error:
                    if readU64(offset) == context {
                        return type == Message.success ? readU16(offset + 14) : nil
                    }
                case Message.sourceUpdate:
                    handleUpdate(at: offset, length: length, live: &live)
                default:
                    break
                }
                offset += length
            }
        }
    }

    private func handleUpdate(at offset: Int, length: Int, live: inout [Int: (inBytes: UInt64, outBytes: UInt64)]) {
        guard let pid = pid(at: offset, length: length) else {
            return
        }
        let rx = readU64(offset + NstatSession.rxBytesOffset)
        let tx = readU64(offset + NstatSession.txBytesOffset)
        let isClosing = readU16(offset + 14) & Message.flagClosing != 0
        if isClosing {
            let current = retired[pid] ?? (0, 0)
            retired[pid] = (current.inBytes + rx, current.outBytes + tx)
        } else {
            let current = live[pid] ?? (0, 0)
            live[pid] = (current.inBytes + rx, current.outBytes + tx)
        }
    }

    private func pid(at offset: Int, length: Int) -> Int? {
        guard length >= NstatSession.descriptorOffset else {
            return nil
        }
        let provider = readU32(offset + NstatSession.providerOffset)
        let pidOffset: Int
        if NstatSession.providersTCP.contains(provider), length == NstatSession.tcpUpdateLength {
            pidOffset = NstatSession.tcpPidOffset
        } else if NstatSession.providersUDP.contains(provider), length == NstatSession.udpUpdateLength {
            pidOffset = NstatSession.udpPidOffset
        } else {
            return nil
        }
        let raw = readU32(offset + pidOffset)
        guard raw > 0, raw <= 99999 else {
            return nil
        }
        return Int(raw)
    }

    private func writeHeader(_ buffer: inout [UInt8], context: UInt64, type: UInt32, flags: UInt16 = 0) {
        writeU64(context, to: &buffer, at: 0)
        writeU32(type, to: &buffer, at: 8)
        writeU16(UInt16(buffer.count), to: &buffer, at: 12)
        writeU16(Message.flagSupportsAggregate | flags, to: &buffer, at: 14)
    }

    private func readU16(_ offset: Int) -> UInt16 {
        receiveBuffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
    }

    private func readU32(_ offset: Int) -> UInt32 {
        receiveBuffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }

    private func readU64(_ offset: Int) -> UInt64 {
        receiveBuffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self) }
    }

    private func writeU16(_ value: UInt16, to buffer: inout [UInt8], at offset: Int) {
        withUnsafeBytes(of: value.littleEndian) { buffer.replaceSubrange(offset..<offset + 2, with: $0) }
    }

    private func writeU32(_ value: UInt32, to buffer: inout [UInt8], at offset: Int) {
        withUnsafeBytes(of: value.littleEndian) { buffer.replaceSubrange(offset..<offset + 4, with: $0) }
    }

    private func writeU64(_ value: UInt64, to buffer: inout [UInt8], at offset: Int) {
        withUnsafeBytes(of: value.littleEndian) { buffer.replaceSubrange(offset..<offset + 8, with: $0) }
    }
}
