//
//  MenuActionTextView.swift
//  eul
//
//  Created by Gao Sun on 2020/10/18.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import AppKit
import SwiftUI

struct MenuHeaderIconButton: View {
    let id: String
    let systemImage: String
    let titleKey: String
    var isActive: Bool = false
    /// Mouse-down delivery while `NSMenu` is tracking (pin on macOS 12–26).
    var usesPointerDown: Bool = false
    var action: (() -> Void)?

    @EnvironmentObject var uiStore: UIStore
    @Environment(\.statusMenuUsesNSMenuTracking) private var usesNSMenuTracking

    private var title: String {
        titleKey.localized()
    }

    private var isOnHover: Bool {
        uiStore.hoveringID == id
    }

    private var deliversOnPointerDown: Bool {
        usesPointerDown && usesNSMenuTracking
    }

    var body: some View {
        Group {
            if deliversOnPointerDown {
                MenuHeaderPointerDownIconButton(
                    systemImage: systemImage,
                    title: title,
                    isActive: isActive,
                    isHighlighted: isOnHover,
                    onPress: { action?() }
                )
            } else {
                Button(action: { action?() }) {
                    Label {
                        Text(title)
                    } icon: {
                        Image(systemName: systemImage)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .labelStyle(.titleAndIcon)
                    .foregroundColor(isActive ? .primary : .secondary)
                    .frame(width: 18, height: 18)
                }
                .labelsHidden()
                .buttonStyle(.plain)
            }
        }
        .menuPinButtonStyle()
        .help(title)
        .accessibilityLabel(title)
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
        .animation(.none)
        .onHover(perform: { hovering in
            if hovering {
                uiStore.hoveringID = id
            } else if uiStore.hoveringID == id {
                uiStore.hoveringID = nil
            }
        })
    }
}

private struct MenuHeaderPointerDownIconButton: NSViewRepresentable {
    let systemImage: String
    let title: String
    let isActive: Bool
    let isHighlighted: Bool
    let onPress: () -> Void

    func makeNSView(context _: Context) -> ExpandedMenuPointerDownControl {
        let control = ExpandedMenuPointerDownControl()
        control.onPress = onPress
        control.toolTip = title
        control.setAccessibilityLabel(title)
        applyAppearance(to: control)
        return control
    }

    func updateNSView(_ control: ExpandedMenuPointerDownControl, context _: Context) {
        control.onPress = onPress
        control.toolTip = title
        control.setAccessibilityLabel(title)
        applyAppearance(to: control)
    }

    private func applyAppearance(to control: ExpandedMenuPointerDownControl) {
        control.contentTintColor = (isActive || isHighlighted) ? .labelColor : .secondaryLabelColor
        if let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            control.image = image.withSymbolConfiguration(config)
        }
    }
}

struct MenuActionTextView: View {
    let id: String
    let text: String
    var action: (() -> Void)?

    @EnvironmentObject var uiStore: UIStore
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var isOnHover: Bool {
        uiStore.hoveringID == id
    }

    var body: some View {
        Button(action: { action?() }) {
            Text(text.localized())
                .font(.system(size: 11, weight: (isOnHover && differentiateWithoutColor) ? .semibold : .regular))
                .underline(isOnHover && differentiateWithoutColor)
                .foregroundColor(isOnHover ? .primary : .secondary)
                .contentShape(Rectangle())
        }
        .menuControlButtonStyle()
        .animation(.none)
        .onHover(perform: { hovering in
            if hovering {
                uiStore.hoveringID = id
            } else if uiStore.hoveringID == id {
                uiStore.hoveringID = nil
            }
        })
    }
}

/// Full-width menu row for the macOS 27 expanded dropdown (Preferences / Quit).
struct MenuDropdownActionRow: View {
    let id: String
    let text: String
    var action: (() -> Void)?

    @EnvironmentObject var uiStore: UIStore
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var isOnHover: Bool {
        uiStore.hoveringID == id
    }

    var body: some View {
        Button(action: { action?() }) {
            HStack {
                Text(text.localized())
                    .font(.system(size: 13))
                    .fontWeight((isOnHover && differentiateWithoutColor) ? .semibold : .regular)
                    .underline(isOnHover && differentiateWithoutColor)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isOnHover ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .animation(.none)
        .onHover(perform: { hovering in
            if hovering {
                uiStore.hoveringID = id
            } else if uiStore.hoveringID == id {
                uiStore.hoveringID = nil
            }
        })
    }
}
