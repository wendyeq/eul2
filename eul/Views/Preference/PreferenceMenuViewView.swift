//
//  PreferenceMenuViewView.swift
//  eul
//
//  Created by Gao Sun on 2020/10/18.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import AppKit
import SwiftUI

extension Preference {
    struct PreferenceMenuViewView: View {
        private let quotaCoordinateSpace = "QuotaProvidersOrdering"
        private let hardwareCoordinateSpace = "HardwareComponentsOrdering"
        @EnvironmentObject var preference: PreferenceStore
        @EnvironmentObject var componentsStore: ComponentsStore<EulMenuComponent>
        @State private var editingMenuTab: PreferenceStore.MenuTab = .hardware

        private func componentBinding(_ component: EulMenuComponent) -> Binding<Bool> {
            Binding(
                get: { componentsStore.activeComponents.contains(component) },
                set: { componentsStore.setActive(component, enabled: $0) }
            )
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                PreferenceInsetFormGroup {
                    PreferenceFormPickerRow(
                        title: "menu.default_tab".localized(fallback: "Open menu on"),
                        selection: $preference.defaultMenuTab,
                        showsDivider: false
                    ) {
                        ForEach(PreferenceStore.MenuTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                }
                Picker("menu.configure_page".localized(fallback: "Configure page"), selection: $editingMenuTab) {
                    ForEach(PreferenceStore.MenuTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: PreferenceChrome.detailContentWidth)
                switch editingMenuTab {
                case .hardware:
                    hardwareSection
                case .quota:
                    quotaProvidersSection
                case .mcp:
                    mcpSection
                }
            }
            .padding(.vertical, 8)
        }

        private var mcpSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(PreferenceStore.MenuTab.mcp.title).subsection()
                PreferenceInsetFormGroup {
                    PreferenceFormSwitchRow(
                        title: "menu.show_mcp".localized(fallback: "Show MCP page"),
                        isOn: componentBinding(.MCP),
                        showsDivider: false
                    )
                }
                Preference.McpView()
            }
        }

        private var hardwareSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(PreferenceStore.MenuTab.hardware.title).subsection()
                PreferenceInsetFormGroup {
                    PreferenceFormSwitchRow(
                        title: "menu.show_hardware".localized(fallback: "Show hardware page"),
                        isOn: $preference.showHardwareMenuTab,
                        showsDivider: false
                    )
                }
                if preference.showHardwareMenuTab {
                    reorderHeader("menu.hardware_components".localized(fallback: "Hardware components"))
                    PreferenceEnabledOrderList(
                        items: preference.orderedHardwareComponents,
                        coordinateSpace: hardwareCoordinateSpace,
                        isOn: componentBinding,
                        move: { preference.moveHardwareComponent(from: $0, to: $1) }
                    ) { component in
                        HStack(spacing: 8) {
                            Image(component.rawValue)
                                .resizable()
                                .frame(width: 12, height: 12)
                            Text(component.localizedDescription)
                                .normal()
                                .fixedSize()
                        }
                    } detail: { component in
                        hardwareDetail(component)
                    }
                }
            }
            .frame(maxWidth: PreferenceChrome.detailContentWidth, alignment: .leading)
        }

        @ViewBuilder
        private func hardwareDetail(_ component: EulMenuComponent) -> some View {
            if componentsStore.activeComponents.contains(component) {
                switch component {
                case .CPU:
                    VStack(spacing: 0) {
                        PreferenceFormRowSeparator()
                        PreferenceFormSwitchRow(
                            title: "menu.show_cpu_top_activities".localized(),
                            isOn: $preference.showCPUTopActivities,
                            showsDivider: true
                        )
                        PreferenceFormPickerRow(
                            title: "cpu_display_mode".localized(),
                            selection: $preference.cpuMenuDisplay,
                            showsDivider: false
                        ) {
                            ForEach(Preference.CpuMenuDisplay.allCases, id: \.self) {
                                Text($0.description).tag($0)
                            }
                        }
                    }
                case .Memory:
                    topActivityRow(
                        "menu.show_ram_top_activities".localized(),
                        isOn: $preference.showRAMTopActivities
                    )
                case .Network:
                    topActivityRow(
                        "menu.show_network_top_activities".localized(),
                        isOn: $preference.showNetworkTopActivities
                    )
                default:
                    EmptyView()
                }
            }
        }

        private var quotaProvidersSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(PreferenceStore.MenuTab.quota.title).subsection()
                PreferenceInsetFormGroup {
                    PreferenceFormSwitchRow(
                        title: "menu.show_quota".localized(fallback: "Show quota page"),
                        isOn: componentBinding(.Quota),
                        showsDivider: false
                    )
                }
                if componentsStore.activeComponents.contains(.Quota) {
                    reorderHeader("menu.quota_providers".localized())
                    PreferenceEnabledOrderList(
                        items: preference.orderedQuotaProviders,
                        coordinateSpace: quotaCoordinateSpace,
                        isOn: quotaVisibilityBinding,
                        move: { preference.moveQuotaProvider(from: $0, to: $1) }
                    ) { provider in
                        Text(provider.titleKey.localized())
                            .normal()
                            .fixedSize()
                    }
                }
            }
            .frame(maxWidth: PreferenceChrome.detailContentWidth, alignment: .leading)
        }

        private func reorderHeader(_ title: String) -> some View {
            HStack {
                Text(title)
                    .subsection()
                Text("component.drag_to_reorder".localized())
                    .subsection()
                    .foregroundColor(Color.gray)
            }
            .fixedSize()
        }

        private func topActivityRow(_ title: String, isOn: Binding<Bool>) -> some View {
            VStack(spacing: 0) {
                PreferenceFormRowSeparator()
                PreferenceFormSwitchRow(
                    title: title,
                    isOn: isOn,
                    showsDivider: false
                )
            }
        }

        private func quotaVisibilityBinding(_ provider: Preference.QuotaProvider) -> Binding<Bool> {
            Binding(
                get: { preference.isQuotaProviderVisible(provider) },
                set: { preference.setQuotaProviderVisible(provider, visible: $0) }
            )
        }
    }
}

struct PreferenceEnabledOrderList<Item: Hashable, Label: View, Detail: View>: View {
    let items: [Item]
    let coordinateSpace: String
    let isOn: (Item) -> Binding<Bool>
    let move: (Int, Int) -> Void
    let label: (Item) -> Label
    let detail: (Item) -> Detail

    @State private var dragging: Item?
    @State private var dragOrigin: Int?
    @State private var dragTranslation: CGFloat = 0
    @State private var draggedRowHeight: CGFloat = 0
    @State private var dragMids: [CGFloat] = []
    @State private var previewDestination: Int?
    @State private var frames: [CGRect] = []

    init(
        items: [Item],
        coordinateSpace: String,
        isOn: @escaping (Item) -> Binding<Bool>,
        move: @escaping (Int, Int) -> Void,
        @ViewBuilder label: @escaping (Item) -> Label,
        @ViewBuilder detail: @escaping (Item) -> Detail
    ) {
        self.items = items
        self.coordinateSpace = coordinateSpace
        self.isOn = isOn
        self.move = move
        self.label = label
        self.detail = detail
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element) { offset, item in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color.gray)
                                .frame(width: 18, height: 22)
                            label(item)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if dragging != nil {
                                return
                            }
                            if hovering {
                                NSCursor.openHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        }
                        .gesture(rowDragGesture(item: item, offset: offset))
                        Toggle("", isOn: isOn(item))
                            .toggleStyle(SwitchToggleStyle())
                            .labelsHidden()
                            .scaleEffect(0.85)
                    }
                    detail(item)
                }
                .preferenceGroupedRowSurface()
                .offset(y: rowOffset(index: offset, item: item))
                .zIndex(dragging == item ? 1 : 0)
                .shadow(color: dragging == item ? Color.black.opacity(0.16) : .clear, radius: dragging == item ? 5 : 0, y: 2)
                .animation(dragging == item ? nil : .easeOut(duration: 0.16), value: previewDestination)
                .background(GeometryReader { geometry in
                    Color.clear.preference(
                        key: OrderListFramePreferenceKey.self,
                        value: [FramePreferenceData(
                            index: offset,
                            frame: geometry.frame(in: CoordinateSpace.named(coordinateSpace))
                        )]
                    )
                })
            }
        }
        .preferenceGroupedListChrome()
        .coordinateSpace(name: coordinateSpace)
        .frame(maxWidth: PreferenceChrome.detailContentWidth, alignment: .leading)
        .onPreferenceChange(OrderListFramePreferenceKey.self) { value in
            guard dragging == nil else {
                return
            }
            var next = frames.count == items.count ? frames : Array(repeating: .zero, count: items.count)
            for data in value where next.indices.contains(data.index) {
                next[data.index] = data.frame
            }
            if next != frames {
                frames = next
            }
        }
    }

    private func rowDragGesture(item: Item, offset: Int) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(coordinateSpace))
            .onChanged { value in
                let translation = value.translation.height
                if dragging == nil {
                    dragging = item
                    dragOrigin = offset
                    draggedRowHeight = frames.indices.contains(offset) ? max(frames[offset].height, 36) : 0
                    dragMids = frames.map(\.midY)
                    previewDestination = offset
                    NSCursor.closedHand.set()
                }
                let destination = dropIndex(from: dragOrigin ?? offset, translation: translation)
                withoutAnimation {
                    dragTranslation = translation
                }
                if previewDestination != destination {
                    previewDestination = destination
                }
            }
            .onEnded { value in
                let origin = dragOrigin ?? offset
                let destination = dropIndex(from: origin, translation: value.translation.height)
                withoutAnimation {
                    if destination != origin {
                        move(origin, destination)
                    }
                    dragging = nil
                    dragOrigin = nil
                    dragTranslation = 0
                    draggedRowHeight = 0
                    previewDestination = nil
                }
                NSCursor.arrow.set()
            }
    }

    private func withoutAnimation(_ update: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, update)
    }

    private func dropIndex(from origin: Int, translation: CGFloat) -> Int {
        guard items.indices.contains(origin), dragMids.indices.contains(origin) else {
            return origin
        }
        let finger = dragMids[origin] + translation
        var best = origin
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for index in items.indices {
            let mid = dragMids.indices.contains(index) ? dragMids[index] : dragMids[origin]
            let distance = abs(finger - mid)
            if distance < bestDistance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    private func rowOffset(index: Int, item: Item) -> CGFloat {
        guard let origin = dragOrigin, dragging != nil, draggedRowHeight > 0 else {
            return 0
        }
        if item == dragging {
            return dragTranslation
        }
        let destination = previewDestination ?? origin
        let height = draggedRowHeight
        if origin < destination, index > origin, index <= destination {
            return -height
        }
        if origin > destination, index >= destination, index < origin {
            return height
        }
        return 0
    }
}

extension PreferenceEnabledOrderList where Detail == EmptyView {
    init(
        items: [Item],
        coordinateSpace: String,
        isOn: @escaping (Item) -> Binding<Bool>,
        move: @escaping (Int, Int) -> Void,
        @ViewBuilder label: @escaping (Item) -> Label
    ) {
        self.init(
            items: items,
            coordinateSpace: coordinateSpace,
            isOn: isOn,
            move: move,
            label: label,
            detail: { _ in EmptyView() }
        )
    }
}

private struct OrderListFramePreferenceKey: PreferenceKey {
    typealias Value = [FramePreferenceData]

    static var defaultValue: [FramePreferenceData] = []

    static func reduce(value: inout [FramePreferenceData], nextValue: () -> [FramePreferenceData]) {
        value += nextValue()
    }
}
