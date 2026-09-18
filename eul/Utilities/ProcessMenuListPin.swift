//
//  ProcessMenuListPin.swift
//  eul
//

import Foundation

/// Keeps one pinned process at row 1 per menu section while the rest of the list keeps live ranking.
enum ProcessMenuListPin {
    static let cpuSection = "cpu"
    static let memorySection = "memory"
    static let networkSection = "network"

    static func pinnedPID(section: String) -> Int? {
        SharedStore.ui.pinnedMenuProcessPIDBySection[section]
    }

    static func mergePinnedFirst<T: ProcessUsage>(
        ranked: [T],
        section: String,
        limit: Int,
        fallback: ((Int) -> T?)? = nil
    ) -> [T] {
        guard let pinnedPID = pinnedPID(section: section) else {
            return Array(ranked.prefix(limit))
        }
        let others = ranked.filter { $0.pid != pinnedPID }
        let pinned: T?
        if let row = ranked.first(where: { $0.pid == pinnedPID }) {
            pinned = row
        } else {
            pinned = fallback?(pinnedPID)
        }
        guard let pinned else {
            return Array(ranked.prefix(limit))
        }
        return [pinned] + others.prefix(max(0, limit - 1))
    }
}
