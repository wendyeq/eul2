//
//  PreferenceDisplayView.swift
//  eul
//
//  Created by Gao Sun on 2020/8/15.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Localize_Swift
import SharedLibrary
import SwiftUI

extension Preference {
    struct DisplayView: View {
        let temperatureUnits: [TemperatureUnit] = [.celius, .fahrenheit]
        let textDisplays = TextDisplay.allCases
        let fontDesigns = FontDesign.allCases
        let appearanceMode = appearance.allCases
        @EnvironmentObject var preference: PreferenceStore

        var body: some View {
            PreferenceInsetFormGroup {
                PreferenceFormPickerRow(
                    title: "language".localized(),
                    selection: $preference.language,
                    showsDivider: true
                ) {
                    ForEach(PreferenceStore.availableLanguages, id: \.self) {
                        Text("language.\($0)".localized())
                            .tag($0)
                    }
                }
                PreferenceFormPickerRow(
                    title: "temp.temperature".localized(),
                    selection: $preference.temperatureUnit,
                    showsDivider: true
                ) {
                    ForEach(temperatureUnits, id: \.self) {
                        Text($0.description)
                            .tag($0)
                    }
                }
                PreferenceFormPickerRow(
                    title: "text_display".localized(),
                    selection: $preference.textDisplay,
                    showsDivider: true
                ) {
                    ForEach(textDisplays) {
                        Text($0.description)
                            .tag($0)
                    }
                }
                PreferenceFormPickerRow(
                    title: "font_design".localized(),
                    selection: $preference.fontDesign,
                    showsDivider: true
                ) {
                    ForEach(fontDesigns) {
                        Text($0.description)
                            .tag($0)
                    }
                }
                if #available(OSX 11, *) {
                    PreferenceFormPickerRow(
                        title: "appearance.mode".localized(),
                        selection: $preference.appearanceMode,
                        showsDivider: false
                    ) {
                        ForEach(appearanceMode) {
                            Text($0.description)
                                .tag($0)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}
