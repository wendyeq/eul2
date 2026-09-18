//
//  StatusBarView.swift
//  eul
//
//  Created by Gao Sun on 2020/9/20.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import SwiftUI

struct StatusBarView: SizeChangeView {
    @EnvironmentObject var preferenceStore: PreferenceStore
    @EnvironmentObject var componentsStore: ComponentsStore<EulComponent>
    @EnvironmentObject var uiStore: UIStore
    var onSizeChange: ((CGSize) -> Void)?

    var spacing: CGFloat {
        preferenceStore.fontDesign == .default ? 12 : 10
    }

    var displayedComponents: [EulComponent] {
        let active = componentsStore.activeComponents
        guard let limit = uiStore.statusBarDisplayedComponentCount else {
            return active
        }
        return Array(active.prefix(max(limit, 1)))
    }

    var body: some View {
        HStack(spacing: spacing) {
            if componentsStore.showComponents {
                ForEach(displayedComponents) { component in
                    component.getView()
                }
            } else {
                Image("eul")
                    .resizable()
                    .frame(width: 16, height: 16)
                    .accessibilityLabel("eul")
            }
            if
                preferenceStore.upgradeMethod == .showInStatusBar,
                preferenceStore.isUpdateAvailable == true
            {
                Image("Upgrade")
                    .resizable()
                    .frame(width: 12, height: 12)
                    .accessibilityLabel("ui.new_version".localized())
            }
        }
        .fixedSize()
        .background(GeometryReader { self.reportSize($0) })
        .onPreferenceChange(SizePreferenceKey.self, perform: { value in
            if let size = value.first {
                onSizeChange?(size)
            }
        })
    }
}
