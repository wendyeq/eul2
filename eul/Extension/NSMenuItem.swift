//
//  NSMenuItem.swift
//  eul
//
//  Created by Gao Sun on 2020/8/23.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Cocoa

extension NSMenuItem {
    static func forDisplay(with text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Keep object/concept images (CPU, GPU, devices) when macOS 27 hides menu icons by default.
    func preferMetricImageVisible() {
        if #available(macOS 27.0, *) {
            preferredImageVisibility = .visible
        }
    }

    /// Verb/action images should stay hidden under the 27 SDK default.
    func hideActionImage() {
        if #available(macOS 27.0, *) {
            preferredImageVisibility = .hidden
        }
    }
}
