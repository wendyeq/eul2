//
//  UIStore.swift
//  eul
//
//  Created by Gao Sun on 2020/10/17.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import AppKit
import Foundation

class UIStore: ObservableObject {
    @Published var hoveringID: String?
    @Published var menuWidth: CGFloat?
    @Published var menuOpened = false
    @Published var isStatusMenuPinned = false
    @Published var activeSection: Preference.Section = .general
    /// `nil` means show every active status-bar component. A number is the leading count that currently fits.
    @Published var statusBarDisplayedComponentCount: Int?
    @Published var statusBarComponentsTruncated = false
    /// One pinned pid per expanded-menu process section (`cpu` / `memory` / `network`).
    @Published var pinnedMenuProcessPIDBySection: [String: Int] = [:]

    func togglePinnedMenuProcess(section: String, pid: Int) {
        if pinnedMenuProcessPIDBySection[section] == pid {
            pinnedMenuProcessPIDBySection.removeValue(forKey: section)
        } else {
            pinnedMenuProcessPIDBySection[section] = pid
        }
    }

    func isMenuProcessPinned(section: String, pid: Int) -> Bool {
        pinnedMenuProcessPIDBySection[section] == pid
    }

    func clearPinnedMenuProcesses() {
        pinnedMenuProcessPIDBySection.removeAll()
    }
}
