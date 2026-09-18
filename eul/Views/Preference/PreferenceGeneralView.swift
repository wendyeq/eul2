//
//  PreferenceGeneralView.swift
//  eul
//
//  Created by Gao Sun on 2020/9/12.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import LaunchAtLogin
import SharedLibrary
import SwiftUI
import SwiftyJSON

extension Preference {
    struct GeneralView: View {
        @ObservedObject var launchAtLogin = LaunchAtLogin.observable
        @ObservedObject var statusBar = StatusBarManager.shared
        @EnvironmentObject var preference: PreferenceStore

        var body: some View {
            VStack(alignment: .leading, spacing: PreferenceChrome.formRowSpacing) {
                HStack(spacing: 12) {
                    if let version = preference.version {
                        Text("eul2 \("ui.version".localized()) \(version)")
                            .inlineSection()
                            .fixedSize()
                    }
                    if let url = preference.repoURL {
                        Button(action: {
                            NSWorkspace.shared.open(url)
                        }) {
                            Text("GitHub")
                        }
                        .focusable(false)
                    }
                    HStack(spacing: 6) {
                        if preference.isUpdateAvailable == nil {
                            ActivityIndicatorView {
                                $0.style = .spinning
                                $0.controlSize = .small
                                $0.startAnimation(nil)
                            }
                            Text("ui.checking_update".localized())
                                .inlineSection()
                                .foregroundColor(.info)
                        } else if preference.checkUpdateFailed {
                        } else if preference.isUpdateAvailable == true {
                            preference.latestReleaseURL.map { url in
                                Button(action: {
                                    NSWorkspace.shared.open(url)
                                }) {
                                    Text("ui.download".localized())
                                }
                                .focusable(false)
                            }
                            Text("ui.new_version".localized())
                                .inlineSection()
                                .foregroundColor(.info)
                        } else {
                            Text("ui.up_to_date".localized())
                                .inlineSection()
                                .foregroundColor(.info)
                        }
                    }
                    .fixedSize()
                }
                PreferenceInsetFormGroup {
                    PreferenceFormPickerRow(
                        title: "ui.upgrade_method".localized(),
                        selection: $preference.upgradeMethod,
                        showsDivider: true
                    ) {
                        ForEach(PreferenceStore.UpgradeMethod.allCases, id: \.self) {
                            Text("ui.upgrade_method.\($0)".localized())
                                .tag($0)
                        }
                    }
                    PreferenceFormSwitchRow(
                        title: "ui.launch_at_login".localized(),
                        isOn: $launchAtLogin.isEnabled,
                        showsDivider: true
                    )
                    PreferenceFormSwitchRow(
                        title: "ui.show_in_menu_bar".localized(),
                        isOn: Binding(
                            get: { statusBar.isItemVisible },
                            set: { statusBar.setItemVisible($0) }
                        ),
                        showsDivider: true
                    )
                    PreferenceFormSwitchRow(
                        title: "ui.check_status_item_visibility".localized(),
                        isOn: $preference.checkStatusItemVisibility,
                        showsDivider: false
                    )
                }
                Text("ui.upgrade_method.\(preference.upgradeMethod.rawValue).description".localized())
                    .secondaryDisplayText()
                Text("ui.show_in_menu_bar.description".localized())
                    .secondaryDisplayText()
            }
            .padding(.vertical, 8)
        }
    }
}
