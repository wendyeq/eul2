//
//  StatusBarItem.swift
//  eul
//
//  Created by Gao Sun on 2020/8/21.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Cocoa
import SwiftUI

extension Notification.Name {
    static let StatusBarMenuShouldClose = Notification.Name("StatusBarMenuShouldClose")
}

final class StatusBarExpandedPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@available(macOS 27.0, *)
private final class StatusBarExpandedInterfaceCoordinator: NSObject, NSStatusItemExpandedInterfaceDelegate {
    weak var owner: StatusBarItem?

    init(owner: StatusBarItem) {
        self.owner = owner
        super.init()
    }

    func statusItem(_: NSStatusItem, didBegin _: NSStatusItemExpandedInterfaceSession) {
        owner?.showExpandedInterface()
    }

    func statusItemDidEndExpandedInterfaceSession(_: NSStatusItem, animated: Bool) {
        owner?.hideExpandedInterface(animated: animated)
    }
}

class StatusBarItem: NSObject, NSMenuDelegate {
    static let launchTime = Date()

    @ObservedObject var preferenceStore = SharedStore.preference
    @ObservedObject var componentsStore = SharedStore.components

    let config: StatusBarConfig
    private let statusBarMenu: NSMenu
    private let item: NSStatusItem
    private var statusView: NSHostingView<AnyView>?
    private var menuView: NSHostingView<AnyView>?
    private var statusMenuCustomItem: NSMenuItem?
    private var expandedPanel: StatusBarExpandedPanel?
    private var expandedCoordinator: AnyObject?
    private var expandedEventMonitor: Any?
    private var expandedGlobalMonitor: Any?
    private var expandedResignActiveObserver: NSObjectProtocol?
    private var expandedResignKeyObserver: NSObjectProtocol?
    private var expandedGeneration = 0
    private var expandedDismissSuppressionDeadline = Date.distantPast
    private var lastToggleCancel = Date.distantPast
    private var shouldCloseObserver: NSObjectProtocol?
    private var visibilityTimer: Timer?
    private var visibilityObservation: NSKeyValueObservation?
    private var statusBarSizeChanged = 0
    private var extraLayoutGeneration = 0
    private var pre27PinPanelPresentationScheduled = false
    private var isStatusBarMenuTracking = false

    /// Called when AppKit updates `NSStatusItem.isVisible` (Control Center, menu-bar settings, or in-app toggle).
    var onVisibilityChange: ((Bool) -> Void)?

    var isVisible: Bool {
        get { item.isVisible }
        set {
            item.isVisible = newValue
        }
    }

    func onSizeChange(size: CGSize, generation: Int) {
        let width = size.width + (Info.isBigSur ? 8 : 12) + (componentsStore.showComponents ? 0 : -8)

        DispatchQueue.main.async { [self] in
            guard generation == extraLayoutGeneration else {
                return
            }
            statusBarSizeChanged += 1
            applyStatusItemWidth(width)
        }
    }

    /// First-layout extras wider than the remaining menu bar are parked off-screen.
    /// Drop trailing status-bar components until the leading ones fit.
    private func applyStatusItemWidth(_ width: CGFloat) {
        let height = AppDelegate.statusBarHeight
        let activeCount = componentsStore.activeComponents.count
        let shown = SharedStore.ui.statusBarDisplayedComponentCount ?? activeCount
        if componentsStore.showComponents, shown > 1, width < 80 {
            return
        }
        if componentsStore.showComponents, shouldDropTrailingStatusBarComponent(measuredWidth: width) {
            dropTrailingStatusBarComponent()
            return
        }
        SharedStore.ui.statusBarComponentsTruncated = shown < activeCount
        item.length = width
        statusView?.setFrameSize(NSSize(width: width, height: height))
    }

    private func shouldDropTrailingStatusBarComponent(measuredWidth: CGFloat) -> Bool {
        let shown = SharedStore.ui.statusBarDisplayedComponentCount ?? componentsStore.activeComponents.count
        guard shown > 1 else {
            return false
        }
        return measuredWidth > Self.maxFittingStatusItemWidth
    }

    private func dropTrailingStatusBarComponent() {
        let activeCount = componentsStore.activeComponents.count
        let shown = SharedStore.ui.statusBarDisplayedComponentCount ?? activeCount
        guard shown > 1 else {
            return
        }
        SharedStore.ui.statusBarDisplayedComponentCount = shown - 1
        SharedStore.ui.statusBarComponentsTruncated = true
        refresh()
    }

    private static var maxFittingStatusItemWidth: CGFloat {
        let screenW = NSScreen.main?.frame.width ?? 1440
        if #available(macOS 27.0, *) {
            return min(220, max(80, screenW * 0.14))
        }
        return min(480, max(140, screenW * 0.32))
    }

    func onMenuSizeChange(size: CGSize) {
        SharedStore.ui.menuWidth = size.width
        menuView?.setFrameSize(NSSize(width: size.width, height: size.height))
        if expandedPanel?.isVisible == true {
            positionExpandedPanel()
        }
    }

    func refresh() {
        extraLayoutGeneration += 1
        let generation = extraLayoutGeneration
        let view = NSHostingView(rootView: config.viewBuilder { [weak self] size in
            self?.onSizeChange(size: size, generation: generation)
        })
        view.setFrameSize(NSSize(width: 0, height: AppDelegate.statusBarHeight))
        item.button?.subviews.forEach { $0.removeFromSuperview() }
        item.button?.addSubview(view)
        statusView = view
        item.button?.setAccessibilityTitle("eul")
        item.button?.setAccessibilityRole(.button)
    }

    func menuWillOpen(_ menu: NSMenu) {
        if #unavailable(macOS 27.0), preparePre27StatusMenuForOpeningAbortsHollowMenu() {
            return
        }
        isStatusBarMenuTracking = true
        SharedStore.ui.menuWidth = menu.size.width
        SharedStore.ui.menuOpened = true
    }

    func menuDidClose(_: NSMenu) {
        isStatusBarMenuTracking = false
        if SharedStore.ui.isStatusMenuPinned {
            if #unavailable(macOS 27.0) {
                schedulePre27PinnedPanelPresentation()
            }
            return
        }
        if isPre27MenuPanelVisible {
            return
        }
        SharedStore.ui.menuOpened = false
        SharedStore.ui.clearPinnedMenuProcesses()
    }

    func checkVisibilityIfNeeded() {
        guard preferenceStore.checkStatusItemVisibility else {
            return
        }

        // add delay on launch due to potential false alarm
        let interval = max(15 + StatusBarItem.launchTime.timeIntervalSinceNow, 1.5)
        visibilityTimer?.invalidate()
        visibilityTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false, block: { _ in
            self.checkStatusItemVisibility()
        })
    }

    func setAppearance(_ appearance: NSAppearance?) {
        statusBarMenu.appearance = appearance
        expandedPanel?.appearance = appearance
        menuView?.appearance = appearance
    }

    func showExpandedInterface() {
        // A toggle-click cancel may be immediately followed by the system
        // beginning a fresh session for the same click. End that session
        // instead of flashing the panel back open.
        if Date().timeIntervalSince(lastToggleCancel) < 0.5 {
            lastToggleCancel = .distantPast
            cancelExpandedInterfaceSession()
            return
        }
        SharedStore.ui.menuOpened = true
        expandedGeneration += 1
        ensureExpandedPanel()
        positionExpandedPanel()
        applyExpandedPanelPinChrome(pinned: SharedStore.ui.isStatusMenuPinned)
        installExpandedInterfaceMonitors()
        expandedPanel?.alphaValue = 1
        expandedPanel?.makeKeyAndOrderFront(nil)
    }

    func toggleStatusMenuPin() {
        if SharedStore.ui.isStatusMenuPinned {
            hideExpandedInterface(animated: true, force: true)
            return
        }
        SharedStore.ui.isStatusMenuPinned = true
        if #available(macOS 27.0, *) {
            applyExpandedPanelPinChrome(pinned: true)
            // End the system session so mouse-leave does not tear the panel down.
            cancelExpandedInterfaceSession()
        } else {
            pinPre27MenuUsingPanel()
        }
    }

    func hideExpandedInterface(animated: Bool, force: Bool = false) {
        if SharedStore.ui.isStatusMenuPinned, !force {
            return
        }
        SharedStore.ui.isStatusMenuPinned = false
        SharedStore.ui.menuOpened = false
        SharedStore.ui.clearPinnedMenuProcesses()
        applyExpandedPanelPinChrome(pinned: false)
        removeExpandedInterfaceMonitors()
        if let panel = expandedPanel, panel.isVisible {
            if animated {
                let generation = expandedGeneration
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.12
                    panel.animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    // A new session may have begun mid-fade; only order out if it didn't.
                    guard let self, self.expandedGeneration == generation else {
                        return
                    }
                    self.finishHidingExpandedPanel(panel)
                })
            } else {
                finishHidingExpandedPanel(panel)
            }
        } else if #unavailable(macOS 27.0) {
            reattachMenuViewFromPinPanelIfNeeded()
        }
    }

    private var isPre27MenuPanelVisible: Bool {
        if #available(macOS 27.0, *) {
            return false
        }
        return expandedPanel?.isVisible == true
    }

    private func pinPre27MenuUsingPanel() {
        SharedStore.ui.menuOpened = true
        beginExpandedDismissSuppression()
        statusBarMenu.cancelTracking()
        schedulePre27PinnedPanelPresentation()
    }

    private func schedulePre27PinnedPanelPresentation() {
        guard #unavailable(macOS 27.0) else {
            return
        }
        guard SharedStore.ui.isStatusMenuPinned else {
            return
        }
        guard !pre27PinPanelPresentationScheduled else {
            return
        }
        pre27PinPanelPresentationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.pre27PinPanelPresentationScheduled = false
            self.presentPre27PinnedPanelIfNeeded()
        }
    }

    private func presentPre27PinnedPanelIfNeeded() {
        guard #unavailable(macOS 27.0) else {
            return
        }
        guard SharedStore.ui.isStatusMenuPinned else {
            return
        }
        guard expandedPanel?.isVisible != true else {
            return
        }
        if isStatusBarMenuTracking {
            schedulePre27PinnedPanelPresentation()
            return
        }
        expandedGeneration += 1
        ensureExpandedPanel()
        positionExpandedPanel()
        applyExpandedPanelPinChrome(pinned: true)
        installExpandedInterfaceMonitors()
        beginExpandedDismissSuppression()
        expandedPanel?.alphaValue = 1
        expandedPanel?.makeKeyAndOrderFront(nil)
        SharedStore.ui.menuOpened = true
    }

    private func finishHidingExpandedPanel(_ panel: StatusBarExpandedPanel) {
        reattachMenuViewFromPinPanelIfNeeded()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    @discardableResult
    private func preparePre27StatusMenuForOpeningAbortsHollowMenu() -> Bool {
        if isPre27MenuPanelVisible {
            if SharedStore.ui.isStatusMenuPinned {
                statusBarMenu.cancelTracking()
                expandedPanel?.makeKeyAndOrderFront(nil)
                SharedStore.ui.menuOpened = true
                return true
            }
            hideExpandedInterface(animated: false, force: true)
        }
        reattachMenuViewFromPinPanelIfNeeded()
        return false
    }

    /// Move the shared hosting view back onto the `NSMenu` item after the pin panel dismisses.
    /// Do not call while `NSMenu` is tracking.
    private func reattachMenuViewFromPinPanelIfNeeded() {
        guard #unavailable(macOS 27.0) else {
            return
        }
        guard !isStatusBarMenuTracking else {
            return
        }
        guard let menuView = menuView, let customItem = statusMenuCustomItem else {
            return
        }
        guard customItem.view !== menuView else {
            return
        }
        menuView.removeFromSuperview()
        customItem.view = menuView
        if expandedPanel?.contentView === menuView {
            expandedPanel?.contentView = nil
        }
    }

    func dismissMenuOrExpandedInterface() {
        cancelExpandedInterfaceSession()
        statusBarMenu.cancelTracking()
        if isPre27MenuPanelVisible {
            hideExpandedInterface(animated: false, force: true)
        }
    }

    /// WWDC26 #289: run the action, then cancel the expanded session (not the reverse).
    func performExpandedMenuAction(_ action: () -> Void) {
        action()
        if SharedStore.ui.isStatusMenuPinned {
            return
        }
        cancelExpandedInterfaceSession()
    }

    /// Process-row 「置于顶部」: yield + activate while eul is still active, then end the session.
    func activateTargetFromExpandedMenu(_ target: NSRunningApplication) {
        _ = target.bringToFrontFromMenu()
        if SharedStore.ui.isStatusMenuPinned {
            return
        }
        cancelExpandedInterfaceSession()
    }

    private func beginExpandedDismissSuppression() {
        expandedDismissSuppressionDeadline = Date().addingTimeInterval(0.5)
    }

    private func shouldSuppressExpandedAutoDismiss() -> Bool {
        Date() < expandedDismissSuppressionDeadline
    }

    private func cancelExpandedInterfaceSession() {
        if #available(macOS 27.0, *) {
            item.expandedInterfaceSession?.cancel()
        }
    }

    /// AppKit ends an NSMenu session on outside-click/Escape itself. A custom
    /// expanded-interface panel gets none of that: per WWDC26 289
    /// ("Modernize your AppKit app") and the NSStatusItem header, the app must
    /// call expandedInterfaceSession?.cancel() whenever other user action
    /// should dismiss the interface, and hide the window in didEnd. The system
    /// only auto-ends the session when focus moves, so detect the rest here:
    /// a GLOBAL mouse monitor for clicks in other apps (a local monitor never
    /// sees those), a local monitor for Escape and the status-item toggle
    /// click, plus resign-key / resign-active backstops.
    private func installExpandedInterfaceMonitors() {
        guard expandedEventMonitor == nil else {
            return
        }
        expandedEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            self?.handleExpandedInterfaceEvent(event) ?? event
        }
        guard expandedGlobalMonitor == nil else {
            return
        }
        // Mouse-only: global key monitoring would need Input Monitoring
        // approval; Escape is covered by the local monitor above.
        expandedGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.handleExpandedInterfaceGlobalClick()
        }
        guard expandedResignActiveObserver == nil else {
            return
        }
        expandedResignActiveObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.shouldSuppressExpandedAutoDismiss() else {
                return
            }
            if SharedStore.ui.isStatusMenuPinned {
                return
            }
            self.dismissExpandedMenuPresentation()
        }
        guard expandedResignKeyObserver == nil else {
            return
        }
        expandedResignKeyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: expandedPanel, queue: .main) { [weak self] _ in
            guard let self, self.expandedPanel?.isVisible == true else {
                return
            }
            DispatchQueue.main.async {
                guard self.expandedPanel?.isVisible == true else {
                    return
                }
                if NSApp.keyWindow === self.expandedPanel {
                    return
                }
                if self.shouldSuppressExpandedAutoDismiss() {
                    return
                }
                if SharedStore.ui.isStatusMenuPinned {
                    return
                }
                self.dismissExpandedMenuPresentation()
            }
        }
    }

    /// End macOS 27 expanded session and/or hide a pre-27 pin panel.
    private func dismissExpandedMenuPresentation(animated: Bool = true) {
        if #available(macOS 27.0, *) {
            cancelExpandedInterfaceSession()
            return
        }
        if expandedPanel?.isVisible == true {
            hideExpandedInterface(animated: animated, force: true)
        }
    }

    private func isScreenPointInsideExpandedPanel(_ screenPoint: NSPoint) -> Bool {
        guard let panel = expandedPanel, panel.isVisible else {
            return false
        }
        let pointInWindow = panel.convertPoint(fromScreen: screenPoint)
        guard let contentView = panel.contentView else {
            return false
        }
        let pointInContent = contentView.convert(pointInWindow, from: nil)
        return contentView.bounds.contains(pointInContent)
    }

    private func isEventInsideExpandedPanel(_ event: NSEvent) -> Bool {
        guard expandedPanel?.isVisible == true else {
            return false
        }
        if event.type == .keyDown {
            return false
        }
        if let panel = expandedPanel, event.window === panel {
            return true
        }
        return isScreenPointInsideExpandedPanel(NSEvent.mouseLocation)
    }

    private func removeExpandedInterfaceMonitors() {
        if let monitor = expandedEventMonitor {
            NSEvent.removeMonitor(monitor)
            expandedEventMonitor = nil
        }
        if let monitor = expandedGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            expandedGlobalMonitor = nil
        }
        if let observer = expandedResignActiveObserver {
            NotificationCenter.default.removeObserver(observer)
            expandedResignActiveObserver = nil
        }
        if let observer = expandedResignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            expandedResignKeyObserver = nil
        }
    }

    /// Global taps cannot swallow events; they only observe. Cancel the
    /// session and let the outside click land where the user aimed.
    private func handleExpandedInterfaceGlobalClick() {
        guard expandedPanel?.isVisible == true else {
            return
        }
        let location = NSEvent.mouseLocation
        if isScreenPointInsideExpandedPanel(location) {
            return
        }
        if SharedStore.ui.isStatusMenuPinned {
            if isPointInStatusButton(location) {
                lastToggleCancel = Date()
                hideExpandedInterface(animated: true, force: true)
            }
            return
        }
        if isPointInStatusButton(location) {
            // Second click on the status item toggles closed. The global tap
            // cannot swallow the click, so stamp it: if the system begins a
            // fresh session for this same click, showExpandedInterface ends
            // it immediately instead of reopening.
            lastToggleCancel = Date()
            cancelExpandedInterfaceSession()
            return
        }
        cancelExpandedInterfaceSession()
    }

    private func isPointInStatusButton(_ location: NSPoint) -> Bool {
        guard let button = item.button, let buttonWindow = button.window else {
            return false
        }
        return NSPointInRect(location, buttonWindow.convertToScreen(button.convert(button.bounds, to: nil)))
    }

    private func handleExpandedInterfaceEvent(_ event: NSEvent) -> NSEvent? {
        guard expandedPanel?.isVisible == true else {
            return event
        }
        if event.type == .keyDown {
            // Escape dismisses, like menu tracking.
            if event.keyCode == 53 {
                hideExpandedInterface(animated: true, force: true)
                cancelExpandedInterfaceSession()
                return nil
            }
            return event
        }
        if isEventInsideExpandedPanel(event) {
            return event
        }
        if SharedStore.ui.isStatusMenuPinned {
            if isPointInStatusButton(NSEvent.mouseLocation) {
                hideExpandedInterface(animated: true, force: true)
                return nil
            }
            return event
        }
        if isPointInStatusButton(NSEvent.mouseLocation) {
            // Second click on the status item toggles closed. Swallow it so the
            // system does not begin a fresh session on the same click.
            cancelExpandedInterfaceSession()
            return nil
        }
        // Click in another eul window: dismiss but let the click through.
        // Clicks in other apps never reach the local monitor; the
        // didResignActive observer cancels the session for those.
        cancelExpandedInterfaceSession()
        return event
    }

    private func checkStatusItemVisibility() {
        // User-hidden extras stay `isVisible == false`. That is not occlusion and must not alert.
        guard item.isVisible else {
            Print("ℹ️ status item hidden by user or system menu-bar settings")
            return
        }

        if item.button?.window?.occlusionState.contains(.visible) == false {
            print("⚠️ status item hidden by system")
            let alert = NSAlert()
            alert.messageText = "ui.hidden_by_system.title".localized()
            alert.informativeText = "ui.hidden_by_system.message".localized()
            alert.alertStyle = .warning
            alert.addButton(withTitle: "ui.hidden_by_system.open".localized())
            alert.addButton(withTitle: "ui.hidden_by_system.dismiss".localized())
            NSApp.activate(ignoringOtherApps: true)

            let result = alert.runModal()
            if result == .alertFirstButtonReturn {
                SharedStore.ui.activeSection = .components
                AppDelegate.openPreferences()
            }
        } else {
            Print("✅ status item is visible")
        }
    }

    private func ensureExpandedPanel() {
        guard let menuView = menuView else {
            return
        }

        if let panel = expandedPanel {
            attachMenuHostingViewToExpandedPanel(menuView, panel: panel)
            return
        }

        let panel = StatusBarExpandedPanel(
            contentRect: NSRect(x: 0, y: 0, width: StatusMenuView.menuWidth, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.autorecalculatesKeyViewLoop = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        attachMenuHostingViewToExpandedPanel(menuView, panel: panel)
        expandedPanel = panel
        applyExpandedPanelPinChrome(pinned: false)
        setAppearance(preferenceStore.appearanceMode.nsAppearance)
    }

    private func attachMenuHostingViewToExpandedPanel(_ menuView: NSHostingView<AnyView>, panel: StatusBarExpandedPanel) {
        if panel.contentView === menuView {
            return
        }
        menuView.removeFromSuperview()
        menuView.wantsLayer = true
        menuView.layer?.backgroundColor = NSColor.clear.cgColor
        menuView.layer?.masksToBounds = true
        menuView.layer?.cornerRadius = MenuChromeMetrics.shellCornerRadius
        panel.contentView = menuView
    }

    /// A pinned panel must not keep `.popUpMenu` level, or it covers every other app.
    private func applyExpandedPanelPinChrome(pinned: Bool) {
        guard let panel = expandedPanel else {
            return
        }
        if pinned {
            panel.isFloatingPanel = false
            panel.level = .normal
            panel.isMovable = true
            panel.collectionBehavior = [.canJoinAllSpaces]
            panel.isMovableByWindowBackground = true
        } else {
            panel.isFloatingPanel = true
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = false
        }
    }

    private func positionExpandedPanel() {
        guard let panel = expandedPanel, let hosting = menuView else {
            return
        }
        let size = hosting.frame.size
        guard size.width > 1, size.height > 1 else {
            return
        }
        if SharedStore.ui.isStatusMenuPinned, panel.isVisible {
            let frame = panel.frame
            panel.setFrame(
                NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height),
                display: true
            )
            return
        }
        guard let button = item.button, let buttonWindow = button.window else {
            return
        }

        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = NSPoint(x: buttonRect.maxX - size.width, y: buttonRect.minY - size.height)
        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            if size.height >= visible.height {
                // Taller than the screen: pin the top so Preferences/Quit stay visible.
                origin.y = visible.maxY - size.height
            } else {
                if origin.y < visible.minY {
                    origin.y = buttonRect.maxY
                }
                if origin.y + size.height > visible.maxY {
                    origin.y = visible.maxY - size.height
                }
                origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
            }
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    init(named: String = "eul") {
        config = getStatusBarConfig()
        statusBarMenu = NSMenu()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusBarMenu.delegate = self
        // Allow Control Center / System Settings → Menu Bar to hide the extra.
        // autosaveName persists that choice across relaunch; do not overwrite isVisible here.
        item.behavior = .removalAllowed
        item.autosaveName = named
        visibilityObservation = item.observe(\.isVisible, options: [.initial, .new]) { [weak self] statusItem, _ in
            self?.onVisibilityChange?(statusItem.isVisible)
        }

        if let menuBuilder = config.menuBuilder {
            let usesExpandedChrome: Bool
            if #available(macOS 27.0, *) {
                usesExpandedChrome = true
            } else {
                usesExpandedChrome = false
            }
            menuView = StatusBarMenuHostingView(rootView: AnyView(
                menuBuilder(onMenuSizeChange)
                    .environment(\.statusMenuExpandedChrome, usesExpandedChrome)
                    .environment(\.statusMenuHeaderIconChrome, true)
                    .environment(\.statusMenuUsesNSMenuTracking, !usesExpandedChrome)
            ))
            menuView?.translatesAutoresizingMaskIntoConstraints = false
            menuView?.setFrameSize(NSSize(width: StatusMenuView.menuWidth, height: 1))

            if #available(macOS 27.0, *) {
                // Custom NSMenu tracking fights Full Keyboard Access. The same SwiftUI
                // dropdown is shown as the system expanded interface instead.
                let coordinator = StatusBarExpandedInterfaceCoordinator(owner: self)
                expandedCoordinator = coordinator
                item.expandedInterfaceDelegate = coordinator
                ensureExpandedPanel()
            } else {
                let customItem = NSMenuItem()
                customItem.view = menuView
                statusMenuCustomItem = customItem
                statusBarMenu.addItem(customItem)
                item.menu = statusBarMenu
            }
        } else {
            item.menu = statusBarMenu
        }

        shouldCloseObserver = NotificationCenter.default.addObserver(forName: .StatusBarMenuShouldClose, object: nil, queue: nil) { [weak self] _ in
            self?.dismissMenuOrExpandedInterface()
        }

        refresh()

        // Small trick to forcely trigger re-render
        // Prevent wrong icon position when not showing status bar components
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            guard statusBarSizeChanged <= 1 else {
                return
            }
            componentsStore.showComponents = componentsStore.showComponents
        }
    }

    deinit {
        visibilityObservation?.invalidate()
        removeExpandedInterfaceMonitors()
        if let observer = shouldCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
