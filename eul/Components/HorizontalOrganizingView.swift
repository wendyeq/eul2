//
//  HorizontalOrganizingView.swift
//  eul
//
//  Created by Gao Sun on 2020/11/24.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import SwiftUI

struct HorizontalOrganizingView<Element: JSONCodabble & Equatable & Hashable, ElementView: View>: View {
    @ObservedObject var componentsStore: ComponentsStore<Element>
    let coordinateSpace: String
    var title: String?
    var buildElementView: (Element) -> ElementView

    @State var dragging: Element?
    @State var frames: [CGRect]
    @GestureState var offsetHeight: CGFloat = 0

    func updateFrame(geometry: GeometryProxy, index: Int) -> some View {
        Color.clear.preference(
            key: FramePreferenceKey.self,
            value: componentsStore.isActiveComponentToggling
                ? []
                : [FramePreferenceData(index: index, frame: geometry.frame(in: CoordinateSpace.named(coordinateSpace)))]
        )
    }

    func activeToggleBinding(for element: Element) -> Binding<Bool> {
        Binding(
            get: { componentsStore.activeComponents.contains(element) },
            set: { isOn in
                withAnimation(.fast) {
                    if isOn {
                        if let index = componentsStore.availableComponents.firstIndex(of: element) {
                            componentsStore.toggleAvailableComponent(at: index)
                        }
                    } else if componentsStore.activeComponents.count > 1,
                              let index = componentsStore.activeComponents.firstIndex(of: element)
                    {
                        componentsStore.toggleActiveComponent(at: index)
                    }
                }
            }
        )
    }

    func availableToggleBinding(for _: Element, at offset: Int) -> Binding<Bool> {
        Binding(
            get: { false },
            set: { isOn in
                guard isOn else {
                    return
                }
                withAnimation(.fast) {
                    componentsStore.toggleAvailableComponent(at: offset)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let title = title {
                    Text(title.localized())
                        .subsection()
                }
                Text("component.drag_to_reorder".localized())
                    .subsection()
                    .foregroundColor(.secondary)
            }
            PreferenceInsetFormGroup {
                if componentsStore.activeComponents.isEmpty {
                    HStack {
                        Spacer()
                        Text("ui.empty".localized())
                            .secondaryDisplayText()
                        Spacer()
                    }
                    .padding(.vertical, PreferenceChrome.formRowInsetVertical)
                }
                ForEach(Array(componentsStore.activeComponents.enumerated()), id: \.element) { offset, element in
                    let isLast = offset == componentsStore.activeComponents.count - 1
                    PreferenceFormSplitRow(showsDivider: !isLast) {
                        buildElementView(element)
                    } control: {
                        Toggle(isOn: activeToggleBinding(for: element)) {
                            EmptyView()
                        }
                        .preferenceFormTrailingSwitch()
                        .disabled(componentsStore.activeComponents.count == 1)
                    }
                    .offset(y: dragging == element ? offsetHeight : 0)
                    .zIndex(dragging == element ? 1 : 0)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .updating($offsetHeight, body: { value, state, _ in
                                state = value.translation.height

                                let currentFrame = frames[offset]

                                if state > 0, offset < componentsStore.activeComponents.count - 1 {
                                    let nextFrame = frames[offset + 1]

                                    if currentFrame.maxY + state > (nextFrame.minY + nextFrame.maxY) / 2 {
                                        DispatchQueue.main.async {
                                            componentsStore.activeComponents.swapAt(offset, offset + 1)
                                        }
                                    }
                                }

                                if state < 0, offset > 0 {
                                    let prevFrame = frames[offset - 1]

                                    if currentFrame.minY + state < (prevFrame.minY + prevFrame.maxY) / 2 {
                                        DispatchQueue.main.async {
                                            componentsStore.activeComponents.swapAt(offset, offset - 1)
                                        }
                                    }
                                }
                            })
                            .onChanged { _ in
                                dragging = element
                            }
                            .onEnded { _ in
                                dragging = nil
                            }
                    )
                    .background(GeometryReader { geometry in
                        updateFrame(geometry: geometry, index: offset)
                    })
                }
            }
            .coordinateSpace(name: coordinateSpace)
            .clipped()

            if componentsStore.availableComponents.count > 0 {
                Text("component.available".localized())
                    .subsection()
                PreferenceInsetFormGroup {
                    ForEach(Array(componentsStore.availableComponents.enumerated()), id: \.element) { offset, element in
                        let isLast = offset == componentsStore.availableComponents.count - 1
                        PreferenceFormSplitRow(showsDivider: !isLast) {
                            buildElementView(element)
                        } control: {
                            Toggle(isOn: availableToggleBinding(for: element, at: offset)) {
                                EmptyView()
                            }
                            .preferenceFormTrailingSwitch()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: PreferenceChrome.detailContentWidth, alignment: .leading)
        .onPreferenceChange(FramePreferenceKey.self, perform: { value in
            for data in value {
                frames[data.index] = data.frame
            }
        })
    }
}

extension HorizontalOrganizingView {
    init(
        componentsStore: ComponentsStore<Element>,
        coordinateSpace: String = "\(String(describing: Element.self))Ordering",
        title: String? = nil,
        buildElementView: @escaping (Element) -> ElementView
    ) {
        self.componentsStore = componentsStore
        _frames = State(initialValue: [CGRect](repeating: .zero, count: componentsStore.totalCount))
        self.coordinateSpace = coordinateSpace
        self.title = title
        self.buildElementView = buildElementView
    }
}
