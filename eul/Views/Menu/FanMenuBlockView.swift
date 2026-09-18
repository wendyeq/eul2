//
//  FanMenuBlockView.swift
//  eul
//
//  Created by Gao Sun on 2020/9/20.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import SwiftUI

struct FanMenuBlockView: View {
    @EnvironmentObject var fanStore: FanStore

    private func fanColumns(start: Int) -> [(title: String, value: String)?] {
        (0..<4).map { offset in
            let index = start + offset
            guard index < fanStore.fans.count else { return nil }
            let fan = fanStore.fans[index]
            return ("\("fan".localized()) \(fan.id + 1)", fan.currentSpeedString)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: MenuMetricGrid.columnSpacing) {
                MenuSectionHeader(title: "fan", iconName: "Fan")
                    .frame(width: MenuMetricGrid.columnWidth, alignment: .leading)
                ForEach(1..<4, id: \.self) { column in
                    fanMetricCell(index: column - 1)
                }
            }
            .frame(width: MenuMetricGrid.rowWidth, alignment: .leading)
            if fanStore.fans.count > 3 {
                ForEach(Array(stride(from: 3, to: fanStore.fans.count, by: 4)), id: \.self) { start in
                    let slice = fanColumns(start: start)
                    CompactEqualSectionRow(items: slice)
                }
            }
        }
        .padding(.top, 2)
        .menuBlock()
    }

    @ViewBuilder
    private func fanMetricCell(index: Int) -> some View {
        if index < fanStore.fans.count {
            let fan = fanStore.fans[index]
            MiniSectionView(
                title: "\("fan".localized()) \(fan.id + 1)",
                value: fan.currentSpeedString
            )
            .frame(width: MenuMetricGrid.columnWidth, alignment: .leading)
        } else {
            Color.clear
                .frame(width: MenuMetricGrid.columnWidth)
                .accessibilityHidden(true)
        }
    }
}
