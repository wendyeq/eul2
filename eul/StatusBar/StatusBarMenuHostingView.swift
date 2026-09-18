//
//  StatusBarMenuHostingView.swift
//  eul
//
//  Created by Gao Sun on 2020/10/17.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import AppKit
import SwiftUI

class StatusBarMenuHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @MainActor @preconcurrency dynamic required init?(coder: NSCoder) {
        super.init(coder: coder)
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    // https://stackoverflow.com/a/2437435/12514940
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false
        window?.backgroundColor = .clear
        layer?.backgroundColor = NSColor.clear.cgColor
        wantsLayer = true
        layer?.masksToBounds = true
        if window is StatusBarExpandedPanel {
            layer?.cornerRadius = MenuChromeMetrics.shellCornerRadius
        } else {
            layer?.cornerRadius = 0
        }
        guard window?.isVisible == true else {
            return
        }
        // Only the pin / expanded panel is ours to key; calling `becomeKey` on the
        // system `NSMenu` window crashes on recent macOS releases.
        if window is StatusBarExpandedPanel {
            window?.becomeKey()
        }
    }
}

/// macOS 15+: `WindowDragGesture` is the supported way to drag a title-less window.
private struct PinnedHeaderWindowDrag: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            if #available(macOS 15.0, *) {
                content
                    .gesture(WindowDragGesture())
                    .allowsWindowActivationEvents(true)
            } else {
                content
            }
        } else {
            content
        }
    }
}

extension View {
    func pinnedHeaderWindowDrag(enabled: Bool) -> some View {
        modifier(PinnedHeaderWindowDrag(enabled: enabled))
    }
}
