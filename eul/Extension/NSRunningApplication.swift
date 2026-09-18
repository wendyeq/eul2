//
//  NSRunningApplication.swift
//  eul
//
//  Created by Gao Sun on 2020/10/17.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import AppKit
import Darwin

extension NSRunningApplication {
    var canBeActivated: Bool {
        activationPolicy == .regular || activationPolicy == .accessory
    }

    /// Brings this app to the foreground from eul's expanded menu (cooperative activation on macOS 14+).
    @discardableResult
    func bringToFrontFromMenu() -> Bool {
        if isHidden {
            unhide()
        }
        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: self)
        }
        if activate() {
            return true
        }
        return activate(options: .activateIgnoringOtherApps)
    }
}

enum RunningApplicationLookup {
    /// Resolves a frontable app for a process row. Network rows usually match by PID; CPU/RAM helpers need bundle or parent lookup.
    static func frontableApplication(
        pid: Int,
        command: String,
        runningApps: [NSRunningApplication] = NSWorkspace.shared.runningApplications
    ) -> NSRunningApplication? {
        guard pid > 0 else {
            return nil
        }
        if let exact = runningApps.first(where: { $0.processIdentifier == pid }), exact.canBeActivated {
            return exact
        }

        if let fromBundle = frontableApplication(containingAppBundleForPID: pid_t(pid), runningApps: runningApps) {
            return fromBundle
        }

        if let fromCommand = appBundleURL(in: command).flatMap({ frontableApplication(bundleURL: $0, runningApps: runningApps) }) {
            return fromCommand
        }

        return frontableApplication(walkingParentsFrom: pid_t(pid), runningApps: runningApps)
    }

    private static func frontableApplication(
        containingAppBundleForPID pid: pid_t,
        runningApps: [NSRunningApplication]
    ) -> NSRunningApplication? {
        guard let path = executablePath(pid: pid),
              let bundleURL = appBundleURL(in: path)
        else {
            return nil
        }
        return frontableApplication(bundleURL: bundleURL, runningApps: runningApps)
    }

    private static func frontableApplication(
        bundleURL: URL,
        runningApps: [NSRunningApplication]
    ) -> NSRunningApplication? {
        let matches = runningApps.filter { $0.bundleURL == bundleURL && $0.canBeActivated }
        if let regular = matches.first(where: { $0.activationPolicy == .regular }) {
            return regular
        }
        return matches.first
    }

    private static func frontableApplication(
        walkingParentsFrom pid: pid_t,
        runningApps: [NSRunningApplication]
    ) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<12 {
            guard let parent = parentPid(of: current), parent > 1 else {
                break
            }
            if let app = runningApps.first(where: { $0.processIdentifier == parent && $0.canBeActivated }) {
                return app
            }
            if let fromBundle = frontableApplication(containingAppBundleForPID: parent, runningApps: runningApps) {
                return fromBundle
            }
            current = parent
        }
        return nil
    }

    private static func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else {
            return nil
        }
        return String(cString: buffer)
    }

    private static func appBundleURL(in path: String) -> URL? {
        guard path.hasPrefix("/") else {
            return nil
        }
        var current = URL(fileURLWithPath: path).deletingLastPathComponent()
        while current.path != "/" {
            if current.pathExtension == "app" {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    private static func parentPid(of pid: pid_t) -> pid_t? {
        guard pid > 0 else {
            return nil
        }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            return nil
        }
        return pid_t(info.pbi_ppid)
    }
}
