//
//  StatusMenuView.swift
//  eul
//
//  Created by Gao Sun on 2020/9/20.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import AppKit
import SharedLibrary
import SwiftUI

struct StatusMenuView: SizeChangeView {
    /// Hosting-view width of the upstream 1.6.2 status-bar dropdown (points).
    static let menuWidth: CGFloat = MenuMetricGrid.hostWidth

    @EnvironmentObject var preferenceStore: PreferenceStore
    @EnvironmentObject var menuComponentsStore: ComponentsStore<EulMenuComponent>
    @EnvironmentObject var uiStore: UIStore
    @Environment(\.statusMenuExpandedChrome) private var expandedChrome
    @Environment(\.statusMenuHeaderIconChrome) private var headerIconChrome
    @Environment(\.statusMenuUsesNSMenuTracking) private var usesNSMenuTracking

    var onSizeChange: ((CGSize) -> Void)?

    private static func expandedComponentsScrollCap() -> CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 800
        return max(180, visible - 120)
    }

    private var availableMenuTabs: [PreferenceStore.MenuTab] {
        var tabs: [PreferenceStore.MenuTab] = []
        if preferenceStore.showHardwareMenuTab {
            tabs.append(.hardware)
        }
        if menuComponentsStore.activeComponents.contains(.Quota) {
            tabs.append(.quota)
        }
        if menuComponentsStore.activeComponents.contains(.MCP) {
            tabs.append(.mcp)
        }
        return tabs
    }

    private var selectedMenuTab: PreferenceStore.MenuTab? {
        availableMenuTabs.contains(uiStore.selectedMenuTab) ? uiStore.selectedMenuTab : availableMenuTabs.first
    }

    private var visibleMenuComponents: [EulMenuComponent] {
        switch selectedMenuTab {
        case .none:
            return []
        case .hardware:
            return preferenceStore.orderedHardwareComponents.filter {
                menuComponentsStore.activeComponents.contains($0)
            }
        case .quota:
            return preferenceStore.showCursorQuota || preferenceStore.showGrokQuota || preferenceStore.showCodexQuota
                ? [.Quota] : []
        case .mcp:
            return [.MCP]
        }
    }

    private var menuEmptyMessage: String {
        if availableMenuTabs.isEmpty {
            return "menu.tab.all_hidden".localized(fallback: "All menu pages are hidden. Open Settings to show one.")
        }
        return "menu.tab.empty".localized(fallback: "Nothing to show. Enable items in Menu View.")
    }

    private var menuTabs: some View {
        HStack(spacing: 3) {
            ForEach(availableMenuTabs) { tab in
                Button {
                    uiStore.selectedMenuTab = tab
                } label: {
                    Text(tab.title)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .foregroundColor(selectedMenuTab == tab ? .primary : .secondary)
                        .background {
                            if selectedMenuTab == tab {
                                RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.22))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedMenuTab == tab ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var menuComponentsStack: some View {
        if visibleMenuComponents.isEmpty {
            Text(menuEmptyMessage)
                .secondaryDisplayText()
                .frame(maxWidth: .infinity, minHeight: 64)
        } else {
            ForEach(Array(visibleMenuComponents.enumerated()), id: \.element.id) { index, component in
                if index > 0 {
                    SeparatorView(menuSection: expandedChrome)
                }
                component.getView()
            }
        }
    }

    var body: some View {
        VStack(spacing: expandedChrome ? MenuExpandedLayout.scrollSectionSpacing : 12) {
            HStack {
                HStack {
                    Text("eul2")
                        .font(.system(size: 12, weight: .semibold))
                    Text("v\(preferenceStore.version ?? "?")")
                        .secondaryDisplayText()
                    if preferenceStore.isUpdateAvailable == true {
                        Text("ui.new_version".localized())
                            .secondaryDisplayText()
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .pinnedHeaderWindowDrag(enabled: uiStore.isStatusMenuPinned && !usesNSMenuTracking)
                if headerIconChrome {
                    HStack(spacing: 8) {
                        MenuHeaderIconButton(
                            id: "menu.preferences",
                            systemImage: "gearshape",
                            titleKey: "menu.preferences",
                            action: AppDelegate.openPreferences
                        )
                        MenuHeaderIconButton(
                            id: "menu.quit",
                            systemImage: "rectangle.portrait.and.arrow.right",
                            titleKey: "menu.quit",
                            action: AppDelegate.quit
                        )
                        MenuHeaderIconButton(
                            id: uiStore.isStatusMenuPinned ? "menu.unpin" : "menu.pin",
                            systemImage: uiStore.isStatusMenuPinned ? "pin.fill" : "pin",
                            titleKey: uiStore.isStatusMenuPinned ? "menu.unpin" : "menu.pin",
                            isActive: uiStore.isStatusMenuPinned,
                            usesPointerDown: true,
                            action: { StatusBarManager.shared.toggleStatusMenuPin() }
                        )
                    }
                } else {
                    MenuActionTextView(id: "menu.preferences", text: "menu.preferences", action: AppDelegate.openPreferences)
                    MenuActionTextView(id: "menu.quit", text: "menu.quit", action: AppDelegate.quit)
                }
            }
            if availableMenuTabs.count > 1 {
                menuTabs
            }
            if expandedChrome {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: MenuExpandedLayout.scrollSectionSpacing) {
                        menuComponentsStack
                    }
                }
                .frame(maxHeight: Self.expandedComponentsScrollCap())
            } else {
                menuComponentsStack
            }
        }
        .padding(.vertical, expandedChrome ? MenuExpandedLayout.shellVerticalPadding : 8)
        .padding(.horizontal, expandedChrome ? MenuExpandedLayout.shellHorizontalPadding : 15)
        .environment(\.menuCompactLayout, expandedChrome)
        .frame(width: Self.menuWidth)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.none)
        .modifier(ExpandedMenuSurfaceLayout(expandedChrome: expandedChrome))
        .background(GeometryReader { self.reportSize($0) })
        .onPreferenceChange(SizePreferenceKey.self, perform: { value in
            if let size = value.first {
                onSizeChange?(size)
            }
        })
        .preferredColorScheme()
    }
}
