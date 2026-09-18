//
//  ContentView.swift
//  eul
//
//  Created by Gao Sun on 2020/6/21.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import SharedLibrary
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var preferenceStore: PreferenceStore
    @EnvironmentObject var componentsStore: ComponentsStore<EulComponent>
    @EnvironmentObject var uiStore: UIStore

    var body: some View {
        ZStack {
            PreferenceWindowRootBackground()
            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    ForEach(Preference.Section.allCases) {
                        Preference.PreferenceSectionView(activeSection: $uiStore.activeSection, section: $0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 10)
                .frame(width: PreferenceChrome.sidebarWidth)
                .preferenceSidebarChrome()

                ScrollView([.vertical], showsIndicators: !Info.isBigSur) {
                    VStack(alignment: .leading, spacing: PreferenceChrome.sectionStackSpacing) {
                        if uiStore.activeSection == .general {
                            SectionView(title: "ui.app".localized()) {
                                Preference.GeneralView()
                            }
                            SectionView(title: "ui.display".localized()) {
                                Preference.DisplayView()
                            }
                            SectionView(title: "ui.refresh_rate".localized()) {
                                Preference.RefreshRateView()
                            }
                        }
                        if uiStore.activeSection == .components {
                            SectionView(title: "ui.display".localized()) {
                                Preference
                                    .ComponentsView()
                                    .padding(.top, 4)
                            }
                            if componentsStore.showComponents {
                                ForEach(EulComponent.allCases) {
                                    Preference.ComponentConfigView(component: $0)
                                }
                            }
                        }
                        if uiStore.activeSection == .menuView {
                            SectionView(title: "ui.display".localized()) {
                                Preference.PreferenceMenuViewView()
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, PreferenceChrome.contentVerticalPadding)
                    .padding(.horizontal, PreferenceChrome.contentHorizontalPadding)
                    .frame(width: PreferenceChrome.detailContentWidth, alignment: .leading)
                }
                .preferenceDetailScrollSurface()
                .background {
                    PreferenceWindowRootBackground()
                }
                .frame(width: PreferenceChrome.detailWidth)
                .frame(maxHeight: .infinity)
            }
        }
        .frame(width: PreferenceChrome.windowWidth, height: PreferenceChrome.windowHeight)
        .id(preferenceStore.language)
        .preferredColorScheme()
    }
}
