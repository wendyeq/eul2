//
//  PreferenceChrome.swift
//  eul
//
//  Softer System Settings–like window chrome without changing prefs IA.
//

import AppKit
import SwiftUI

enum PreferenceChrome {
    static let windowWidth: CGFloat = 560
    static let windowHeight: CGFloat = 420
    static let sidebarWidth: CGFloat = 156
    static var detailWidth: CGFloat {
        windowWidth - sidebarWidth
    }

    static var detailContentWidth: CGFloat {
        detailWidth - contentHorizontalPadding * 2
    }

    static let sidebarRowCornerRadius: CGFloat = 6
    static let groupedRowCornerRadius: CGFloat = 6
    /// Vertical gap between preference form rows (matches System Settings density).
    static let formRowSpacing: CGFloat = 8
    /// Minimum row height so labels and switches share a common vertical centerline.
    static let formControlRowMinHeight: CGFloat = 22
    static let formRowInsetHorizontal: CGFloat = 12
    static let formRowInsetVertical: CGFloat = 6
    /// Trailing switch column (mini `NSSwitch`); keep narrow so labels stay single-line.
    static let formTrailingSwitchSlotWidth: CGFloat = 44
    /// Trailing pop-up menu column; aligned to the same outer edge as switches.
    static let formTrailingPickerSlotWidth: CGFloat = 104
    static let contentHorizontalPadding: CGFloat = 20
    static let contentVerticalPadding: CGFloat = 16
    static let sectionStackSpacing: CGFloat = 20
}

struct PreferenceSidebarMaterial: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
        nsView.material = .sidebar
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

struct PreferenceWindowRootBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}

extension View {
    /// Sidebar trailing rule + sidebar material (preferences only).
    func preferenceSidebarChrome() -> some View {
        background {
            PreferenceSidebarMaterial()
                .ignoresSafeArea()
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.separator.opacity(0.45))
                .frame(width: 1)
        }
    }

    func preferenceSidebarRow(isSelected: Bool) -> some View {
        padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: PreferenceChrome.sidebarRowCornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                }
            }
            .contentShape(Rectangle())
    }

    /// Lighter grouped row than solid `controlBackground` cards.
    func preferenceGroupedRowSurface() -> some View {
        padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background {
                RoundedRectangle(cornerRadius: PreferenceChrome.groupedRowCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            }
    }

    func preferenceGroupedListChrome() -> some View {
        padding(8)
            .background {
                RoundedRectangle(cornerRadius: PreferenceChrome.groupedRowCornerRadius, style: .continuous)
                    .strokeBorder(Color.separator.opacity(0.55), lineWidth: 1)
            }
    }

    /// Hides SwiftUI’s default scroll plate so AppKit window background shows through (matches System Settings).
    func preferenceDetailScrollSurface() -> some View {
        modifier(PreferenceDetailScrollSurface())
    }

    /// Compact macOS switch for preferences (not iOS-sized `.regular`).
    func preferenceFormTrailingSwitch() -> some View {
        toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
    }
}

extension Text {
    func preferenceFormLabel() -> some View {
        font(.body)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct PreferenceDetailScrollSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

extension Notification.Name {
    /// AppKit posts this when the app’s effective appearance changes (not exposed on all SDK Swift interfaces).
    static let applicationDidChangeEffectiveAppearance = Notification.Name("NSApplicationDidChangeEffectiveAppearanceNotification")
}

enum PreferenceWindowAppearance {
    static func apply(_ mode: Preference.appearance, to window: NSWindow?) {
        NSApp.appearance = mode.nsAppearance
        window?.appearance = mode.nsAppearance
        refreshChrome(on: window)
    }

    static func refreshChrome(on window: NSWindow?) {
        guard let window else {
            return
        }
        let background = NSColor.windowBackgroundColor
        window.backgroundColor = background
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = background.cgColor
        window.contentView?.needsDisplay = true
    }
}
