//
//  MenuActionButtonView.swift
//  eul
//
//  Created by Gao Sun on 2020/10/16.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import AppKit
import SwiftUI

struct MenuActionButtonView: View {
    let id: String
    var imageName: String?
    var systemImage: String?
    let toolTip: String?
    /// Expanded menu only: do not end the session after this action (e.g. process list pin).
    var expandedKeepsMenuOpen = false
    var action: (() -> Void)?

    @EnvironmentObject var uiStore: UIStore
    @Environment(\.statusMenuExpandedChrome) private var expandedChrome

    private var label: String {
        toolTip?.localized() ?? ""
    }

    var isOnHover: Bool {
        uiStore.hoveringID == id
    }

    private var usesSymbolChrome: Bool {
        expandedChrome && systemImage != nil
    }

    var body: some View {
        if usesSymbolChrome {
            symbolButton
        } else {
            legacyButton
        }
    }

    private func runAction() {
        guard let action else {
            return
        }
        if expandedChrome, !expandedKeepsMenuOpen {
            StatusBarManager.shared.performExpandedMenuAction(action)
        } else {
            action()
        }
    }

    private var symbolButton: some View {
        ExpandedMenuPointerDownSymbolButton(
            systemImage: systemImage ?? "",
            label: label,
            isHighlighted: isOnHover,
            onPress: runAction
        )
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
        .accessibilityLabel(label)
        .help(label)
        .animation(.none)
        .onHover(perform: hoverHandler)
    }

    private var legacyButton: some View {
        Button(action: runAction) {
            Group {
                if let imageName = imageName {
                    Image(imageName)
                        .resizable()
                        .frame(width: 14, height: 14)
                } else {
                    Text(label)
                        .font(.system(size: 10, weight: .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(isOnHover ? .primary : .secondary)
        .contentShape(Rectangle())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel(label)
        .modifier(MenuActionButtonTooltip(useSystemHelp: false, label: label, isOnHover: isOnHover))
        .animation(.none)
        .onHover(perform: hoverHandler)
    }

    private func hoverHandler(_ hovering: Bool) {
        if hovering {
            uiStore.hoveringID = id
        } else if uiStore.hoveringID == id {
            uiStore.hoveringID = nil
        }
    }
}

private struct MenuActionButtonTooltip: ViewModifier {
    let useSystemHelp: Bool
    let label: String
    let isOnHover: Bool

    func body(content: Content) -> some View {
        if useSystemHelp {
            content.help(label)
        } else {
            content.toolTip(label, isVisible: isOnHover)
        }
    }
}

// SwiftUI `Button` delivers on mouse-up; the expanded session often ends on mouse-down.
// Fire on mouse-down, then end the session after the action (WWDC26 #289).
private struct ExpandedMenuPointerDownSymbolButton: NSViewRepresentable {
    let systemImage: String
    let label: String
    let isHighlighted: Bool
    let onPress: () -> Void

    func makeNSView(context _: Context) -> ExpandedMenuPointerDownControl {
        let control = ExpandedMenuPointerDownControl()
        control.onPress = onPress
        control.toolTip = label
        control.setAccessibilityLabel(label)
        applyAppearance(to: control)
        return control
    }

    func updateNSView(_ control: ExpandedMenuPointerDownControl, context _: Context) {
        control.onPress = onPress
        control.toolTip = label
        control.setAccessibilityLabel(label)
        applyAppearance(to: control)
    }

    private func applyAppearance(to control: ExpandedMenuPointerDownControl) {
        control.contentTintColor = isHighlighted ? .labelColor : .secondaryLabelColor
        if let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: label) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            control.image = image.withSymbolConfiguration(config)
        }
    }
}

final class ExpandedMenuPointerDownControl: NSButton {
    var onPress: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .regularSquare
        isBordered = false
        imagePosition = .imageOnly
        setButtonType(.momentaryChange)
        focusRingType = .none
        setFrameSize(NSSize(width: 24, height: 24))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with _: NSEvent) {
        onPress?()
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
