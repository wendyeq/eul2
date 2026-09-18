//
//  PreferenceMenuViewView.swift
//  eul
//
//  Created by Gao Sun on 2020/10/18.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import SwiftUI

extension Preference {
    struct PreferenceMenuViewView: View {
        private let coordinateSpace = "MenuComponentsOrdering"
        private let quotaCoordinateSpace = "QuotaProvidersOrdering"
        @EnvironmentObject var preference: PreferenceStore
        @EnvironmentObject var componentsStore: ComponentsStore<EulMenuComponent>
        @State var dragging: EulMenuComponent?
        @State var frames: [CGRect] = .init(repeating: .zero, count: EulMenuComponent.allCases.count)
        @GestureState var offsetHeight: CGFloat = 0
        @State var draggingQuota: Preference.QuotaProvider?
        @State var quotaDragOrigin: Int?
        @State var quotaDragTranslation: CGFloat = 0
        @State var quotaFrames: [CGRect] = .init(repeating: .zero, count: Preference.QuotaProvider.allCases.count)

        func updateFrame(geometry: GeometryProxy, index: Int) -> some View {
            Color.clear.preference(
                key: FramePreferenceKey.self,
                value: componentsStore.isActiveComponentToggling
                    ? []
                    : [FramePreferenceData(index: index, frame: geometry.frame(in: CoordinateSpace.named(coordinateSpace)))]
            )
        }

        func updateQuotaFrame(geometry: GeometryProxy, index: Int) -> some View {
            Color.clear.preference(
                key: QuotaFramePreferenceKey.self,
                value: [FramePreferenceData(index: index, frame: geometry.frame(in: CoordinateSpace.named(quotaCoordinateSpace)))]
            )
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                PreferenceInsetFormGroup {
                    PreferenceFormSwitchRow(
                        title: "menu.show_cpu_top_activities".localized(),
                        isOn: $preference.showCPUTopActivities,
                        showsDivider: true
                    )
                    PreferenceFormSwitchRow(
                        title: "menu.show_ram_top_activities".localized(),
                        isOn: $preference.showRAMTopActivities,
                        showsDivider: true
                    )
                    PreferenceFormSwitchRow(
                        title: "menu.show_network_top_activities".localized(),
                        isOn: $preference.showNetworkTopActivities,
                        showsDivider: true
                    )
                    PreferenceFormPickerRow(
                        title: "cpu_display_mode".localized(),
                        selection: $preference.cpuMenuDisplay,
                        showsDivider: false
                    ) {
                        ForEach(Preference.CpuMenuDisplay.allCases, id: \.self) {
                            Text($0.description)
                                .tag($0)
                        }
                    }
                }
                quotaProvidersSection
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ui.menu_view".localized())
                                .subsection()
                            Text("component.drag_to_reorder".localized())
                                .subsection()
                                .foregroundColor(Color.gray)
                        }
                        .fixedSize()
                        VStack(spacing: 4) {
                            if componentsStore.activeComponents.isEmpty {
                                HStack {
                                    Spacer()
                                    Text("ui.empty".localized())
                                        .secondaryDisplayText()
                                    Spacer()
                                }
                            }
                            ForEach(Array(componentsStore.activeComponents.enumerated()), id: \.element) { offset, element in
                                HStack(spacing: 8) {
                                    Image(element.rawValue)
                                        .resizable()
                                        .frame(width: 12, height: 12)
                                    Text(element.localizedDescription)
                                        .normal()
                                        .fixedSize()
                                    Spacer()
                                    Image("X")
                                        .resizable()
                                        .frame(width: 8, height: 8)
                                        .padding(.horizontal, 4)
                                        .contentShape(Rectangle())
                                        .foregroundColor(Color.gray)
                                        .onHover {
                                            guard self.dragging == nil else {
                                                return
                                            }
                                            if $0 {
                                                NSCursor.pointingHand.push()
                                            } else {
                                                NSCursor.pop()
                                            }
                                        }
                                        .onTapGesture {
                                            withAnimation(.fast) {
                                                self.componentsStore.toggleActiveComponent(at: offset)
                                            }
                                        }
                                        .padding(.trailing, -4)
                                }
                                .preferenceGroupedRowSurface()
                                .offset(y: self.dragging == element ? self.offsetHeight : 0)
                                .zIndex(self.dragging == element ? 1 : 0)
                                .contentShape(Rectangle())
                                .gesture(DragGesture()
                                    .updating(self.$offsetHeight, body: { value, state, _ in
                                        state = value.translation.height

                                        let currentFrame = self.frames[offset]

                                        if state > 0, offset < self.componentsStore.activeComponents.count - 1 {
                                            let nextFrame = self.frames[offset + 1]

                                            if currentFrame.maxY + state > (nextFrame.minY + nextFrame.maxY) / 2 {
                                                DispatchQueue.main.async {
                                                    self.componentsStore.activeComponents.swapAt(offset, offset + 1)
                                                }
                                            }
                                        }

                                        if state < 0, offset > 0 {
                                            let prevFrame = self.frames[offset - 1]

                                            if currentFrame.minY + state < (prevFrame.minY + prevFrame.maxY) / 2 {
                                                DispatchQueue.main.async {
                                                    self.componentsStore.activeComponents.swapAt(offset, offset - 1)
                                                }
                                            }
                                        }
                                    })
                                    .onChanged { _ in
                                        self.dragging = element
                                    }
                                    .onEnded { _ in
                                        self.dragging = nil
                                    }
                                )
                                .background(GeometryReader { geometry in
                                    self.updateFrame(geometry: geometry, index: offset)
                                })
                            }
                        }
                        .preferenceGroupedListChrome()
                        .clipped()
                        .coordinateSpace(name: coordinateSpace)
                        .frame(maxWidth: PreferenceChrome.detailContentWidth, alignment: .leading)
                    }
                    if componentsStore.availableComponents.count > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("component.available".localized())
                                    .subsection()
                                Text("component.click_to_append".localized())
                                    .subsection()
                                    .foregroundColor(Color.gray)
                            }
                            .fixedSize()
                            VStack(spacing: 4) {
                                ForEach(Array(componentsStore.availableComponents.enumerated()), id: \.element) { offset, element in
                                    HStack(spacing: 8) {
                                        Image(element.rawValue)
                                            .resizable()
                                            .frame(width: 12, height: 12)
                                        Text(element.localizedDescription)
                                            .normal()
                                            .fixedSize()
                                        Spacer()
                                    }
                                    .preferenceGroupedRowSurface()
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.fast) {
                                            self.componentsStore.toggleAvailableComponent(at: offset)
                                        }
                                    }
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.border, lineWidth: 1)
                            )
                            .clipped()
                            .frame(maxWidth: PreferenceChrome.detailContentWidth, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: PreferenceChrome.detailContentWidth, alignment: .leading)
            }
            .padding(.vertical, 8)
            .onPreferenceChange(FramePreferenceKey.self, perform: { value in
                for data in value {
                    self.frames[data.index] = data.frame
                }
            })
            .onPreferenceChange(QuotaFramePreferenceKey.self, perform: { value in
                for data in value {
                    self.quotaFrames[data.index] = data.frame
                }
            })
        }

        private var quotaProvidersSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("menu.quota_providers".localized())
                        .subsection()
                    Text("component.drag_to_reorder".localized())
                        .subsection()
                        .foregroundColor(Color.gray)
                }
                .fixedSize()
                VStack(spacing: 4) {
                    ForEach(Array(preference.orderedQuotaProviders.enumerated()), id: \.element) { offset, provider in
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color.gray)
                                .frame(width: 18, height: 22)
                                .contentShape(Rectangle())
                                .gesture(
                                    DragGesture(minimumDistance: 2)
                                        .onChanged { value in
                                            if draggingQuota == nil {
                                                draggingQuota = provider
                                                quotaDragOrigin = offset
                                            }
                                            quotaDragTranslation = value.translation.height
                                        }
                                        .onEnded { value in
                                            let origin = quotaDragOrigin ?? offset
                                            let destination = quotaDropIndex(
                                                from: origin,
                                                translation: value.translation.height
                                            )
                                            if destination != origin {
                                                preference.moveQuotaProvider(from: origin, to: destination)
                                            }
                                            draggingQuota = nil
                                            quotaDragOrigin = nil
                                            quotaDragTranslation = 0
                                        }
                                )
                            Text(provider.titleKey.localized())
                                .normal()
                                .fixedSize()
                            Spacer()
                            Toggle("", isOn: quotaVisibilityBinding(provider))
                                .toggleStyle(SwitchToggleStyle())
                                .labelsHidden()
                                .scaleEffect(0.85)
                        }
                        .preferenceGroupedRowSurface()
                        .offset(y: quotaRowOffset(index: offset, provider: provider))
                        .zIndex(draggingQuota == provider ? 1 : 0)
                        .animation(nil, value: preference.quotaProviderOrder)
                        .background(GeometryReader { geometry in
                            updateQuotaFrame(geometry: geometry, index: offset)
                        })
                    }
                }
                .preferenceGroupedListChrome()
                .clipped()
                .coordinateSpace(name: quotaCoordinateSpace)
                .frame(maxWidth: PreferenceChrome.detailContentWidth, alignment: .leading)
            }
            .frame(maxWidth: PreferenceChrome.detailContentWidth, alignment: .leading)
        }

        private func quotaVisibilityBinding(_ provider: Preference.QuotaProvider) -> Binding<Bool> {
            Binding(
                get: { preference.isQuotaProviderVisible(provider) },
                set: { preference.setQuotaProviderVisible(provider, visible: $0) }
            )
        }

        private func quotaRowSpan(around index: Int) -> CGFloat {
            let frames = quotaFrames
            guard frames.indices.contains(index), frames[index].height > 0 else {
                return 36
            }
            if index + 1 < frames.count, frames[index + 1].height > 0 {
                return abs(frames[index + 1].midY - frames[index].midY)
            }
            if index > 0, frames[index - 1].height > 0 {
                return abs(frames[index].midY - frames[index - 1].midY)
            }
            return max(frames[index].height + 4, 36)
        }

        private func quotaDropIndex(from origin: Int, translation: CGFloat) -> Int {
            let count = preference.orderedQuotaProviders.count
            guard count > 0 else {
                return origin
            }
            let span = max(quotaRowSpan(around: origin), 1)
            let delta = Int((translation / span).rounded())
            return min(count - 1, max(0, origin + delta))
        }

        private func quotaRowOffset(index: Int, provider: Preference.QuotaProvider) -> CGFloat {
            guard let origin = quotaDragOrigin, draggingQuota != nil else {
                return 0
            }
            if provider == draggingQuota {
                return quotaDragTranslation
            }
            let destination = quotaDropIndex(from: origin, translation: quotaDragTranslation)
            let span = quotaRowSpan(around: origin)
            if origin < destination, index > origin, index <= destination {
                return -span
            }
            if origin > destination, index >= destination, index < origin {
                return span
            }
            return 0
        }
    }
}

private struct QuotaFramePreferenceKey: PreferenceKey {
    typealias Value = [FramePreferenceData]

    static var defaultValue: [FramePreferenceData] = []

    static func reduce(value: inout [FramePreferenceData], nextValue: () -> [FramePreferenceData]) {
        value += nextValue()
    }
}
