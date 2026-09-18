//
//  NetworkTrafficAccumulator.swift
//  eul
//

import Darwin
import Foundation

struct NetworkTrafficTotals {
    var todayInBytes: UInt64
    var todayOutBytes: UInt64
    var bootInBytes: UInt64
    var bootOutBytes: UInt64
}

final class NetworkTrafficAccumulator {
    private enum Storage {
        static let defaultsKey = "eul.networkTrafficAccumulator"
    }

    private struct PersistedState: Codable {
        var calendarDay: String
        var todayInBytes: UInt64
        var todayOutBytes: UInt64
        var bootIdentity: String
        var bootInBytes: UInt64
        var bootOutBytes: UInt64
        var lastDevice: String?
        var lastInBytes: UInt64
        var lastOutBytes: UInt64
    }

    private var calendarDay: String
    private var todayInBytes: UInt64
    private var todayOutBytes: UInt64
    private var bootIdentity: String
    private var bootInBytes: UInt64
    private var bootOutBytes: UInt64
    private var lastDevice: String?
    private var lastInBytes: UInt64
    private var lastOutBytes: UInt64

    init() {
        let day = Self.currentCalendarDay()
        let boot = Self.currentBootIdentity()
        if
            let data = UserDefaults.standard.data(forKey: Storage.defaultsKey),
            let saved = try? JSONDecoder().decode(PersistedState.self, from: data)
        {
            calendarDay = saved.calendarDay
            todayInBytes = saved.todayInBytes
            todayOutBytes = saved.todayOutBytes
            bootIdentity = saved.bootIdentity
            bootInBytes = saved.bootInBytes
            bootOutBytes = saved.bootOutBytes
            lastDevice = saved.lastDevice
            lastInBytes = saved.lastInBytes
            lastOutBytes = saved.lastOutBytes
        } else {
            calendarDay = day
            todayInBytes = 0
            todayOutBytes = 0
            bootIdentity = boot
            bootInBytes = 0
            bootOutBytes = 0
            lastDevice = nil
            lastInBytes = 0
            lastOutBytes = 0
        }
        rollCalendarDayIfNeeded()
        rollBootSessionIfNeeded()
    }

    func snapshot() -> NetworkTrafficTotals {
        rollCalendarDayIfNeeded()
        rollBootSessionIfNeeded()
        return totals()
    }

    func ingest(device: String, usage: Info.NetworkUsage) -> NetworkTrafficTotals {
        rollCalendarDayIfNeeded()
        rollBootSessionIfNeeded()

        if lastDevice != device {
            lastDevice = device
            lastInBytes = usage.inBytes
            lastOutBytes = usage.outBytes
            persist()
            return totals()
        }

        if lastInBytes == 0, lastOutBytes == 0, usage.inBytes > 0 || usage.outBytes > 0 {
            lastInBytes = usage.inBytes
            lastOutBytes = usage.outBytes
            persist()
            return totals()
        }

        let deltaIn = Self.byteDelta(from: lastInBytes, to: usage.inBytes)
        let deltaOut = Self.byteDelta(from: lastOutBytes, to: usage.outBytes)

        todayInBytes += deltaIn
        todayOutBytes += deltaOut
        bootInBytes += deltaIn
        bootOutBytes += deltaOut

        lastInBytes = usage.inBytes
        lastOutBytes = usage.outBytes
        persist()
        return totals()
    }

    private func totals() -> NetworkTrafficTotals {
        NetworkTrafficTotals(
            todayInBytes: todayInBytes,
            todayOutBytes: todayOutBytes,
            bootInBytes: bootInBytes,
            bootOutBytes: bootOutBytes
        )
    }

    private func rollCalendarDayIfNeeded() {
        let day = Self.currentCalendarDay()
        guard day != calendarDay else {
            return
        }
        calendarDay = day
        todayInBytes = 0
        todayOutBytes = 0
        persist()
    }

    private func rollBootSessionIfNeeded() {
        let boot = Self.currentBootIdentity()
        guard boot != bootIdentity else {
            return
        }
        bootIdentity = boot
        bootInBytes = 0
        bootOutBytes = 0
        lastDevice = nil
        lastInBytes = 0
        lastOutBytes = 0
        persist()
    }

    private func persist() {
        let state = PersistedState(
            calendarDay: calendarDay,
            todayInBytes: todayInBytes,
            todayOutBytes: todayOutBytes,
            bootIdentity: bootIdentity,
            bootInBytes: bootInBytes,
            bootOutBytes: bootOutBytes,
            lastDevice: lastDevice,
            lastInBytes: lastInBytes,
            lastOutBytes: lastOutBytes
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Storage.defaultsKey)
        }
    }

    private static func currentCalendarDay() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func currentBootIdentity() -> String {
        let bootSeconds = bootTimeSeconds().map(String.init) ?? "0"
        let uuid = bootSessionUUID() ?? ""
        return "\(bootSeconds)-\(uuid)"
    }

    private static func bootTimeSeconds() -> Int64? {
        var boottime = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &boottime, &size, nil, 0) == 0 else {
            return nil
        }
        return Int64(boottime.tv_sec)
    }

    private static func bootSessionUUID() -> String? {
        var size: size_t = 0
        guard sysctlbyname("kern.bootsessionuuid", nil, &size, nil, 0) == 0, size > 1 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.bootsessionuuid", &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return String(cString: buffer)
    }

    /// Delta between kernel byte counter samples (netstat `ibytes` / `obytes`).
    private static func byteDelta(from previous: UInt64, to current: UInt64) -> UInt64 {
        if current >= previous {
            return current - previous
        }
        if previous > 512 * 1024 * 1024, current < previous / 2 {
            return (UInt64.max - previous) + current + 1
        }
        return 0
    }
}
