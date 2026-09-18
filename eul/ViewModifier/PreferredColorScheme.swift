//
//  PreferredColorScheme.swift
//  eul
//
//  Created by Gao Sun on 2021/3/18.
//  Copyright © 2021 Gao Sun. All rights reserved.
//

import AppKit
import SwiftUI

extension View {
    func preferredColorScheme() -> some View {
        modifier(PreferredColorScheme())
    }
}

struct PreferredColorScheme: ViewModifier {
    @EnvironmentObject var preferenceStore: PreferenceStore
    @State private var systemAppearanceEpoch = 0

    func body(content: Content) -> some View {
        Group {
            if #available(OSX 11, *) {
                content
                    // Always pass optional scheme so switching to「自动」clears a prior light/dark override.
                    .preferredColorScheme(preferenceStore.appearanceMode.colorScheme)
            } else {
                content
            }
        }
        .id(appearanceViewIdentity)
        .onReceive(NotificationCenter.default.publisher(for: .applicationDidChangeEffectiveAppearance)) { _ in
            guard preferenceStore.appearanceMode == .auto else {
                return
            }
            systemAppearanceEpoch += 1
        }
        .onReceive(
            DistributedNotificationCenter.default().publisher(
                for: Notification.Name("AppleInterfaceThemeChangedNotification")
            )
        ) { _ in
            guard preferenceStore.appearanceMode == .auto else {
                return
            }
            systemAppearanceEpoch += 1
        }
    }

    private var appearanceViewIdentity: String {
        let mode = preferenceStore.appearanceMode.rawValue
        if preferenceStore.appearanceMode == .auto {
            return "\(mode)-\(systemAppearanceEpoch)"
        }
        return mode
    }
}
