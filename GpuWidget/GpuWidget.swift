//
//  GpuWidget.swift
//  GpuWidget
//
//  Created by Gao Sun on 2021/1/24.
//  Copyright © 2021 Gao Sun. All rights reserved.
//

import Intents
import Localize_Swift
import SharedLibrary
import SwiftUI
import WidgetKit

struct Provider: StandardProvider {
    typealias WidgetEntry = GpuEntry
}

struct GpuWidgetEntryView: View {
    var preferenceEntry = Container.get(PreferenceEntry.self) ?? PreferenceEntry()
    var entry: Provider.Entry

    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                Spacer()
                HStack(alignment: .top) {
                    Image("GPU")
                        .resizable()
                        .frame(width: 12, height: 12)
                    Spacer()
                    if let temp = entry.temp {
                        Text(temp.formatTemp(unit: preferenceEntry.temperatureUnit))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
                HStack {
                    Text(entry.usageString)
                        .widgetTitle()
                    Spacer()
                }
                .padding(.bottom, 24)
                if entry.isValid {
                    HStack {
                        Group {
                            WidgetSectionView(
                                title: "cpu.temperature".localized(),
                                value: entry.temp.map { $0.formatTemp(unit: preferenceEntry.temperatureUnit) } ?? "N/A"
                            )
                            WidgetSectionView(title: "power.gpu.short".localized(), value: entry.powerString)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Spacer()
            }
            .padding(16)
            if !entry.isValid {
                WidgetNotAvailbleView(text: "widget.not_available".localized())
            }
        }
        .widgetContainerBackground()
    }
}

@main
struct GpuWidget: Widget {
    let kind: String = GpuEntry.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            GpuWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("widget.gpu.title".localized())
        .description("widget.gpu.description".localized())
        .supportedFamilies([.systemSmall])
    }
}
