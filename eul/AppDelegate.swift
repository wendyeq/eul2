//
//  AppDelegate.swift
//  eul
//
//  Created by Gao Sun on 2020/6/21.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Cocoa
import Combine
import Localize_Swift
import SharedLibrary
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var isSleeping = false
    private var updateMethodCancellable: AnyCancellable?
    private var appearanceCancellable: AnyCancellable?

    var window: NSWindow!
    @ObservedObject var preferenceStore = SharedStore.preference

    func applicationDidFinishLaunching(_: Notification) {
        let contentView = ContentView()
        window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: PreferenceChrome.windowWidth,
                height: PreferenceChrome.windowHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.center()
        window.setFrameAutosaveName("Eul Preferences")
        let hosting = NSHostingView(rootView: contentView.withGlobalEnvironmentObjects())
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor.windowBackgroundColor
        window.isOpaque = true
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.delegate = self

        if #available(OSX 11, *) {
            PreferenceWindowAppearance.apply(preferenceStore.appearanceMode, to: window)
            appearanceCancellable = preferenceStore.$appearanceMode
                .removeDuplicates()
                .sink { [weak self] mode in
                    DispatchQueue.main.async {
                        guard let self else {
                            return
                        }
                        PreferenceWindowAppearance.apply(mode, to: self.window)
                    }
                }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(systemEffectiveAppearanceDidChange),
                name: .applicationDidChangeEffectiveAppearance,
                object: nil
            )
        }

        // comment out for not showing window at login. no proper solution currently, tracking:
        // https://github.com/sindresorhus/LaunchAtLogin/issues/33
        // window.makeKeyAndOrderFront(nil)
        // NSApp.activate(ignoringOtherApps: true)

        SmcControl.shared.subscribe()
        StatusBarManager.shared.checkVisibilityIfNeeded()
        if preferenceStore.mcpHubEnabled {
            SharedStore.mcp.applyEnabled(true)
        }
        wakeUp()

        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { _ in
            print("😪 going to sleep")
            self.sleep()
        }
        notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { _ in
            print("🤩 woke up")
            self.wakeUp()
        }
        updateMethodCancellable = preferenceStore.$upgradeMethod.sink { _ in
            DispatchQueue.main.async {
                self.checkUpdateRepeatedly()
            }
        }
    }

    @objc private func systemEffectiveAppearanceDidChange() {
        guard preferenceStore.appearanceMode == .auto else {
            return
        }
        PreferenceWindowAppearance.apply(.auto, to: window)
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        print("🤚 should terminate")
        SmcControl.shared.close()
        Task {
            await McpHub.shared.stop()
            await MainActor.run {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func wakeUp() {
        isSleeping = false
        refreshSMCRepeatedly()
        refreshNetworkRepeatedly()
        SharedStore.quota.resume()
        checkUpdateRepeatedly()
    }

    func sleep() {
        isSleeping = true
        SharedStore.quota.pause()
    }

    func applicationWillTerminate(_: Notification) {
        // Insert code here to tear down your application
    }
}

// MARK: Static Methods

extension AppDelegate {
    static var statusBarHeight: CGFloat {
        NSStatusBar.system.thickness
    }

    static func openPreferences() {
        (NSApp.delegate as! AppDelegate).window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .StatusBarMenuShouldClose, object: nil)
    }

    static func quit() {
        NSApplication.shared.terminate(self)
    }
}

// MARK: Repeating Methods

extension AppDelegate {
    func refreshSMCRepeatedly() {
        guard !isSleeping else {
            return
        }

        NotificationCenter.default.post(name: .SMCShouldRefresh, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(preferenceStore.smcRefreshRate)) { [self] in
            refreshSMCRepeatedly()
        }
    }

    func refreshNetworkRepeatedly() {
        guard !isSleeping else {
            return
        }

        NotificationCenter.default.post(name: .NetworkShouldRefresh, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(preferenceStore.networkRefreshRate)) { [self] in
            refreshNetworkRepeatedly()
        }
    }

    func checkUpdateRepeatedly() {
        guard !isSleeping, preferenceStore.upgradeMethod != .none else {
            return
        }

        preferenceStore.checkUpdate()
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(60 * 60)) { [self] in
            checkUpdateRepeatedly()
        }
    }
}
