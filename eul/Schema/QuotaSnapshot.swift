//
//  QuotaSnapshot.swift
//  eul
//

import Foundation
import Localize_Swift

struct QuotaMeter: Equatable {
    let id: String
    let labelKey: String
    let usedPercent: Double
    let windowStart: Date?
    let resetsAt: Date?
}

struct QuotaProviderSnapshot: Equatable {
    enum Kind: Equatable {
        /// First open / not fetched yet — never show login in this state.
        case pending
        case unsigned
        case ready
        case failed
    }

    var kind: Kind
    var meters: [QuotaMeter]

    static let pending = QuotaProviderSnapshot(kind: .pending, meters: [])

    static let unsigned = QuotaProviderSnapshot(kind: .unsigned, meters: [])

    static let failedEmpty = QuotaProviderSnapshot(kind: .failed, meters: [])

    static func merging(previous: QuotaProviderSnapshot, incoming: QuotaProviderSnapshot) -> QuotaProviderSnapshot {
        if incoming.kind == .failed, !previous.meters.isEmpty {
            return QuotaProviderSnapshot(kind: .failed, meters: previous.meters)
        }
        return incoming
    }
}

enum QuotaCountdown {
    static func text(resetsAt: Date?, now: Date = Date()) -> String {
        guard let resetsAt else {
            return ""
        }
        let delta = resetsAt.timeIntervalSince(now)
        if delta <= 0 {
            return "quota.reset_soon".localized()
        }
        let totalMin = Int(delta / 60)
        let days = totalMin / 1440
        let hours = (totalMin % 1440) / 60
        let mins = totalMin % 60
        let body: String
        if days > 0 {
            body = "\(days)d \(hours)h"
        } else {
            body = "\(hours)h \(mins)m"
        }
        return String(format: "quota.reset_in".localized(), body)
    }
}

enum QuotaWindowElapsed {
    static func percent(start: Date?, end: Date?, now: Date = Date()) -> Double? {
        guard let start, let end, end > start else {
            return nil
        }
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else {
            return nil
        }
        let raw = now.timeIntervalSince(start) / duration * 100
        return min(100, max(0, raw))
    }
}

enum QuotaTimestamp {
    static func date(fromAPI value: Any?) -> Date? {
        if let string = value as? String {
            if let parsed = ISO8601DateFormatter().date(from: string) {
                return parsed
            }
            if let millis = Double(string) {
                return date(fromSecondsOrMillis: millis)
            }
            return nil
        }
        if let number = number(fromAPI: value) {
            return date(fromSecondsOrMillis: number)
        }
        return nil
    }

    static func number(fromAPI value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let number = value as? Double {
            return number
        }
        if let number = value as? Int {
            return Double(number)
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    static func date(fromSecondsOrMillis value: Double) -> Date? {
        guard value > 0, value.isFinite else {
            return nil
        }
        if value < 1e12 {
            return Date(timeIntervalSince1970: value)
        }
        return Date(timeIntervalSince1970: value / 1000)
    }

    static func clampPercent(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return min(100, max(0, value))
    }
}
