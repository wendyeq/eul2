//
//  Double.swift
//  eul
//
//  Created by Gao Sun on 2020/9/16.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Foundation

public extension Double {
    var percentageString: String {
        (isNaN || isInfinite) ? "N/A" : String(format: "%.0f%%", self * 100)
    }

    var memoryString: String {
        if isNaN || isInfinite {
            return "N/A"
        }
        return self < 1.0 ? String(Int(self * 1000.0)) + " MB" : String(format: "%.2f", self) + " GB"
    }

    var widgetMemoryString: String {
        if isNaN || isInfinite {
            return "N/A"
        }
        if self < 1.0 {
            return "\(Int(self * 1000.0)) MB"
        }
        return String(format: "%.1f GB", self)
    }

    func toFixed(_ decimal: Int) -> String {
        String(format: "%.\(decimal)f", self)
    }

    /// Status-menu process stats: at most three fraction digits, trailing zeros dropped.
    func menuStatDecimalString(maxFractionDigits: Int = 3) -> String {
        if isNaN || isInfinite {
            return "N/A"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = max(0, maxFractionDigits)
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: self)) ?? toFixed(maxFractionDigits)
    }

    var menuStatPercentString: String {
        menuStatDecimalString(maxFractionDigits: 3) + "%"
    }

    var zeroOrAbove: Double {
        isNaN || isLess(than: 0) ? 0 : self
    }
}
