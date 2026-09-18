//
//  StatusBarManager.swift
//  eul
//
//  Created by Gao Sun on 2020/8/22.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import AppKit
import Combine
import SwiftUI

class StatusBarManager: ObservableObject {
    static let shared = StatusBarManager()

    @ObservedObject var preferenceStore = SharedStore.preference
    @ObservedObject var componentsStore = SharedStore.components
    @Published var isItemVisible = true
    private var activeCancellable: AnyCancellable?
    private var displayCancellable: AnyCancellable?
    private var showComponentsCancellable: AnyCancellable?
    private var showIconCancellable: AnyCancellable?
    private var fontDesignCancellable: AnyCancellable?
    private var appearanceModeCancellable: AnyCancellable?
    private let item = StatusBarItem()

    init() {
        item.onVisibilityChange = { [weak self] visible in
            DispatchQueue.main.async {
                guard let self = self, self.isItemVisible != visible else {
                    return
                }
                self.isItemVisible = visible
            }
        }
        isItemVisible = item.isVisible
        // w/o the delay items will have a chance of not appearing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.subscribe()
        }
    }

    func checkVisibilityIfNeeded() {
        item.checkVisibilityIfNeeded()
    }

    func setItemVisible(_ visible: Bool) {
        item.isVisible = visible
    }

    func toggleStatusMenuPin() {
        item.toggleStatusMenuPin()
    }

    func performExpandedMenuAction(_ action: @escaping () -> Void) {
        item.performExpandedMenuAction(action)
    }

    func activateTargetFromExpandedMenu(_ target: NSRunningApplication) {
        item.activateTargetFromExpandedMenu(target)
    }

    func subscribe() {
        // TO-DO: refactor
        activeCancellable = SharedStore.components.$activeComponents.dropFirst().sink {
            self.render(components: $0)
        }
        displayCancellable = preferenceStore.$textDisplay.dropFirst().sink { _ in
            self.rebuildStatusItem()
        }
        showComponentsCancellable = SharedStore.components.$showComponents.dropFirst().sink { _ in
            self.rebuildStatusItem()
        }
        showIconCancellable = preferenceStore.$showIcon.dropFirst().sink { _ in
            self.rebuildStatusItem()
        }
        fontDesignCancellable = preferenceStore.$fontDesign.dropFirst().sink { _ in
            self.rebuildStatusItem()
        }
        // Disable in Catalina to avoid protential crash
        if #available(OSX 11, *) {
            appearanceModeCancellable = preferenceStore.$appearanceMode.sink { value in
                DispatchQueue.main.async {
                    self.item.setAppearance(value.nsAppearance)
                }
            }
        }
    }

    func refresh() {
        DispatchQueue.main.async {
            self.item.refresh()
        }
    }

    func render(components _: [EulComponent]) {
        // Refresh content only. Toggling isVisible would overwrite the user's
        // Control Center / menu-bar setting and break autosaveName persistence.
        rebuildStatusItem()
    }

    private func rebuildStatusItem() {
        SharedStore.ui.statusBarDisplayedComponentCount = nil
        SharedStore.ui.statusBarComponentsTruncated = false
        refresh()
    }
}
