//
//  DiskMenuBlockView.swift
//  eul
//
//  Created by Gao Sun on 2021/1/23.
//  Copyright © 2021 Gao Sun. All rights reserved.
//

import SharedLibrary
import SwiftUI

struct DiskRowView: View {
    @EnvironmentObject var diskStore: DiskStore
    @State var isEjecting = false

    var disk: DiskList.Disk

    func refresh() {
        isEjecting = false
        diskStore.refresh()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(disk.name)
                    .secondaryDisplayText()
                    .lineLimit(1)
                Spacer(minLength: 4)
                if disk.isEjectable {
                    if isEjecting {
                        ActivityIndicatorView {
                            $0.style = .spinning
                            $0.controlSize = .mini
                            $0.startAnimation(nil)
                        }
                        .fixedSize()
                    } else {
                        MenuActionButtonView(
                            id: "disk-\(disk.name)-eject",
                            imageName: "Eject",
                            toolTip: "disk.eject"
                        ) {
                            ejectVolume()
                        }
                    }
                }
            }
            .zIndex(1)
            .frame(width: MenuMetricGrid.rowWidth, alignment: .leading)
            CompactQuadSectionRow(
                c0: ("disk.used", disk.usedSizeString),
                c1: ("disk.free", disk.freeSizeString),
                c2: ("disk.read", disk.readSpeedString),
                c3: ("disk.write", disk.writeSpeedString)
            )
        }
    }

    private func ejectVolume() {
        isEjecting = true
        let path = disk.path
        DispatchQueue.main.async {
            do {
                try DiskVolumeEject.unmountAndEject(path: path)
                refresh()
            } catch {
                isEjecting = false
                let alert = NSAlert()
                alert.messageText = error.localizedDescription
                alert.alertStyle = .informational
                NSApp.activate(ignoringOtherApps: true)
                alert.runModal()
            }
        }
    }
}

struct DiskMenuBlockView: View {
    @EnvironmentObject var diskStore: DiskStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuSectionHeader(title: "component.disk", iconName: "Disk")
            if let list = diskStore.list {
                ForEach(list.disks) {
                    DiskRowView(disk: $0)
                }
            } else {
                Text("N/A".localized())
                    .placeholder()
                    .padding(.bottom, 4)
            }
            diskStore.ssdTemperature.map { temp in
                CompactQuadSectionRow(
                    c0: ("temp.ssd", SmcControl.shared.formatTemp(temp)),
                    c1: nil,
                    c2: nil,
                    c3: nil
                )
            }
        }
        .padding(.top, 2)
        .menuBlock()
    }
}
