//
//  GpuEntry.swift
//  SharedLibrary
//
//  Created by Gao Sun on 2021/1/24.
//  Copyright © 2021 Gao Sun. All rights reserved.
//

import Foundation

@available(macOSApplicationExtension 11, *)
public struct GpuEntry: SharedWidgetEntry {
    public init(date: Date = Date(), outdated: Bool = false, usage: Double? = nil, temp: Double? = nil, powerW: Double? = nil) {
        self.date = date
        self.outdated = outdated
        self.usage = usage
        self.temp = temp
        self.powerW = powerW
    }

    public init(date: Date, outdated: Bool) {
        self.date = date
        self.outdated = outdated
    }

    public static let containerKey = "GpuEntry"
    public static let kind = "GpuWidget"
    public static let sample = GpuEntry(usage: 42, temp: 55, powerW: 6.5)

    public var date = Date()
    public var outdated = false
    public var usage: Double?
    public var temp: Double?
    public var powerW: Double?

    public var usageString: String {
        guard isValid, let usage = usage else {
            return "N/A"
        }
        return String(format: "%.0f%%", usage)
    }

    public var powerString: String {
        guard isValid, let powerW = powerW else {
            return "N/A"
        }
        if powerW < 20 {
            return String(format: "%.1f W", powerW)
        }
        return String(format: "%.0f W", powerW)
    }
}
