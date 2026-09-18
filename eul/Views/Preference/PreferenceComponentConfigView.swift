//
//  PreferenceComponentConfigView.swift
//  eul
//
//  Created by Gao Sun on 2020/11/22.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import Localize_Swift
import SharedLibrary
import SwiftUI

extension Preference {
    struct ComponentTextConfigView<Component: Equatable & JSONCodabble & Hashable & LocalizedStringConvertible>: View {
        @EnvironmentObject var componentsStore: ComponentsStore<Component>

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                PreferenceInsetFormGroup {
                    PreferenceFormSwitchRow(
                        title: "component.show_text".localized(),
                        isOn: $componentsStore.showComponents,
                        showsDivider: false
                    )
                }
                HorizontalOrganizingView(componentsStore: componentsStore) { component in
                    HStack {
                        Text(component.localizedDescription)
                            .preferenceFormLabel()
                    }
                }
            }
        }
    }

    struct ComponentConfigView: View {
        @EnvironmentObject var batteryStore: BatteryStore
        @EnvironmentObject var componentConfigStore: ComponentConfigStore
        @EnvironmentObject var diskStore: DiskStore
        @EnvironmentObject var networkStore: NetworkStore

        var component: EulComponent
        var config: Binding<EulComponentConfig> {
            $componentConfigStore[component]
        }

        var body: some View {
            SectionView(title: component.localizedDescription) {
                VStack(alignment: .leading, spacing: PreferenceChrome.formRowSpacing) {
                    PreferenceInsetFormGroup {
                        PreferenceFormSwitchRow(
                            title: "component.show_icon".localized(),
                            isOn: config.showIcon,
                            showsDivider: config.wrappedValue.component.isGraphAvailable
                                || config.wrappedValue.component.isDiskSelectionAvailable
                                || config.wrappedValue.component.isNetworkInterfaceSelectionAvailable
                        )
                        if config.wrappedValue.component.isGraphAvailable {
                            PreferenceFormSwitchRow(
                                title: "component.show_graph".localized(),
                                isOn: config.showGraph,
                                showsDivider: config.wrappedValue.component.isDiskSelectionAvailable
                                    || config.wrappedValue.component.isNetworkInterfaceSelectionAvailable
                            )
                        }
                        if
                            config.wrappedValue.component.isDiskSelectionAvailable,
                            let disks = diskStore.list?.disks
                        {
                            PreferenceFormPickerRow(
                                title: "disk.select".localized(),
                                selection: config.diskSelection,
                                showsDivider: config.wrappedValue.component.isNetworkInterfaceSelectionAvailable
                            ) {
                                Text("disk.all".localized())
                                    .tag("")
                                ForEach(disks) {
                                    Text($0.name)
                                        .tag($0.name)
                                }
                            }
                        }
                        if config.wrappedValue.component.isNetworkInterfaceSelectionAvailable {
                            PreferenceFormPickerRow(
                                title: "network.port.select".localized(),
                                selection: config.networkPortSelection,
                                showsDivider: false
                            ) {
                                Text(networkStore.autoPortDesscription)
                                    .tag("")
                                ForEach(networkStore.ports) {
                                    Text($0.description)
                                        .tag($0.device)
                                }
                            }
                        }
                    }
                    if component == .CPU {
                        ComponentTextConfigView<CpuTextComponent>()
                    }
                    if component == .GPU {
                        ComponentTextConfigView<GpuTextComponent>()
                    }
                    if component == .Memory {
                        ComponentTextConfigView<MemoryTextComponent>()
                    }
                    if SmcControl.shared.isFanValid, component == .Fan {
                        ComponentTextConfigView<FanTextComponent>()
                    }
                    if component == .Network {
                        ComponentTextConfigView<NetworkTextComponent>()
                    }
                    if batteryStore.isValid, component == .Battery {
                        ComponentTextConfigView<BatteryTextComponent>()
                    }
                    if component == .Disk {
                        ComponentTextConfigView<DiskTextComponent>()
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }
}
