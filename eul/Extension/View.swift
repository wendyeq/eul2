//
//  View.swift
//  eul
//
//  Created by Gao Sun on 2020/9/11.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import AppKit
import SwiftUI

private struct StatusMenuExpandedChromeKey: EnvironmentKey {
    static let defaultValue = false
}

private struct MenuCompactLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var statusMenuExpandedChrome: Bool {
        get { self[StatusMenuExpandedChromeKey.self] }
        set { self[StatusMenuExpandedChromeKey.self] = newValue }
    }

    var menuCompactLayout: Bool {
        get { self[MenuCompactLayoutKey.self] }
        set { self[MenuCompactLayoutKey.self] = newValue }
    }
}

enum MenuChromeMetrics {
    static let shellCornerRadius: CGFloat = 6
}

enum MenuExpandedLayout {
    static let shellVerticalPadding: CGFloat = 6
    static let shellHorizontalPadding: CGFloat = 14
    static let blockVerticalPadding: CGFloat = 5
    static let sectionSpacing: CGFloat = 6
    static let metricRowSpacing: CGFloat = 5
    static let processListSpacing: CGFloat = 5
    static let sectionSeparatorPadding: CGFloat = 2
    static let scrollSectionSpacing: CGFloat = 2
    static let processRowMinHeight: CGFloat = 24

    static func sectionVStackSpacing(compact: Bool) -> CGFloat {
        compact ? sectionSpacing : 8
    }

    static func metricRowSpacing(compact: Bool) -> CGFloat {
        compact ? metricRowSpacing : 6
    }
}

/// Fixed trailing geometry for process rows in the expanded menu (aligned across rows).
enum MenuExpandedProcessRow {
    static let cpuStatWidth: CGFloat = 52
    static let memoryStatsWidth: CGFloat = 96
    static let networkStatsWidth: CGFloat = 96
    static let actionSlotSize: CGFloat = 24
    static let actionCount = 3
    static let actionSpacing: CGFloat = 4
    static let statsToActionsSpacing: CGFloat = 4

    static func trailingClusterWidth(statsWidth: CGFloat) -> CGFloat {
        let actionsWidth = CGFloat(actionCount) * actionSlotSize
            + CGFloat(actionCount - 1) * actionSpacing
        return statsWidth + statsToActionsSpacing + actionsWidth
    }
}

/// Clips expanded dropdown content to the glass shell so the hosting window does not show a dark rectangular matte in dark mode.
struct ExpandedMenuSurfaceLayout: ViewModifier {
    let expandedChrome: Bool

    func body(content: Content) -> some View {
        if expandedChrome {
            let shape = RoundedRectangle(cornerRadius: MenuChromeMetrics.shellCornerRadius, style: .continuous)
            content
                .compositingGroup()
                .background {
                    StatusMenuChrome()
                }
                .clipShape(shape)
        } else {
            content
                .background {
                    StatusMenuChrome()
                }
        }
    }
}

struct StatusMenuChrome: View {
    @Environment(\.statusMenuExpandedChrome) private var expandedChrome
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    var body: some View {
        Group {
            if expandedChrome {
                chromeFill
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private var chromeFill: some View {
        let shape = RoundedRectangle(cornerRadius: MenuChromeMetrics.shellCornerRadius, style: .continuous)
        if #available(macOS 26.0, *), !reduceTransparency, !increaseContrast {
            shape.glassEffect(.regular, in: shape)
        } else {
            ZStack {
                MenuChromeVisualEffectView()
                    .clipShape(shape)
                shape.stroke(Color.menuBorder.opacity(increaseContrast ? 0.9 : 0.35), lineWidth: increaseContrast ? 1 : 0.5)
            }
        }
    }
}

private struct MenuChromeVisualEffectView: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
        nsView.material = .menu
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

private struct MenuBlockModifier: ViewModifier {
    var radius: CGFloat
    @Environment(\.statusMenuExpandedChrome) private var expandedChrome
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    func body(content: Content) -> some View {
        if expandedChrome {
            content
                .padding(.vertical, MenuExpandedLayout.blockVerticalPadding)
                .padding(.horizontal, MenuMetricGrid.blockHorizontalInset)
        } else {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            content
                .padding(.vertical, 8)
                .padding(.horizontal, MenuMetricGrid.blockHorizontalInset)
                .background {
                    ZStack {
                        if increaseContrast || reduceTransparency {
                            shape.fill(Color(NSColor.textBackgroundColor))
                        } else {
                            shape.fill(.regularMaterial)
                        }
                        shape.stroke(Color.menuBorder.opacity(increaseContrast ? 1 : 0.55), lineWidth: increaseContrast ? 1.5 : 1)
                    }
                }
        }
    }
}

extension View {
    func menuInfo() -> some View {
        font(.system(size: 14, weight: .regular))
            .foregroundColor(.info)
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.top, -2)
            .padding(.bottom, 4)
            .fixedSize()
    }

    func menuBlock(radius: CGFloat = 8) -> some View {
        modifier(MenuBlockModifier(radius: radius))
    }

    func metricAccessibility(titleKey: String, value: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(titleKey.localized())
            .accessibilityValue(value)
    }

    func statusBarAccessibility(componentKey: String, values: [String]) -> some View {
        accessibilityElement(children: .combine)
            .accessibilityLabel(componentKey.localized())
            .accessibilityValue(values.filter { !$0.isEmpty }.joined(separator: ", "))
    }

    func menuControlButtonStyle() -> some View {
        modifier(MenuControlButtonStyle())
    }

    func menuPinButtonStyle() -> some View {
        modifier(MenuPinButtonStyle())
    }
}

private struct MenuControlButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.plain)
    }
}

private struct MenuPinButtonStyle: ViewModifier {
    @Environment(\.statusMenuExpandedChrome) private var expandedChrome

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), expandedChrome {
            content
                .buttonStyle(.glass)
                .controlSize(.small)
        } else {
            content.buttonStyle(.plain)
        }
    }
}
