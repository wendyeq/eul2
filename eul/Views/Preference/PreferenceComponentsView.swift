//
//  PreferenceComponentsView.swift
//  eul
//
//  Created by Gao Sun on 2020/8/15.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import SwiftUI

extension Preference {
    struct ComponentsView: View {
        @EnvironmentObject var componentsStore: ComponentsStore<EulComponent>
        @EnvironmentObject var uiStore: UIStore

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                PreferenceInsetFormGroup {
                    PreferenceFormSwitchRow(
                        title: "ui.show_components_in_status_bar".localized(),
                        isOn: $componentsStore.showComponents,
                        showsDivider: false
                    )
                }
                Text("ui.status_bar_capacity.hint".localized())
                    .secondaryDisplayText()
                if uiStore.statusBarComponentsTruncated, let shown = uiStore.statusBarDisplayedComponentCount {
                    Text(String(format: "ui.status_bar_capacity.truncated".localized(), shown, componentsStore.activeComponents.count))
                        .secondaryDisplayText()
                }
                if componentsStore.showComponents {
                    HorizontalOrganizingView(
                        componentsStore: componentsStore,
                        title: "component.status_bar"
                    ) { component in
                        HStack {
                            Image(component.rawValue)
                                .resizable()
                                .frame(width: 12, height: 12)
                            Text(component.localizedDescription)
                                .preferenceFormLabel()
                        }
                    }
                }
            }
        }
    }
}
