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

    var onSizeChange: ((CGSize) -> Void)?

    private static func expandedComponentsScrollCap() -> CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 800
        return max(180, visible - 120)
    }

    @ViewBuilder
    private var menuComponentsStack: some View {
        ForEach(Array(menuComponentsStore.activeComponents.enumerated()), id: \.element.id) { index, component in
            if index > 0 {
                SeparatorView(menuSection: expandedChrome)
            }
            component.getView()
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
                .pinnedHeaderWindowDrag(enabled: uiStore.isStatusMenuPinned)
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
            if expandedChrome {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: MenuExpandedLayout.scrollSectionSpacing) {
                        menuComponentsStack
                    }
                }
                .frame(maxHeight: Self.expandedComponentsScrollCap())
            } else {
                ForEach(Array(menuComponentsStore.activeComponents.enumerated()), id: \.element.id) { index, component in
                    if index > 0 {
                        SeparatorView(padding: 2)
                    }
                    component.getView()
                }
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
