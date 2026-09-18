//
//  MiniSectionView.swift
//  eul
//
//  Created by Gao Sun on 2020/9/20.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import SwiftUI

/// Shared geometry for equal-width metric columns inside the 345pt status menu.
enum MenuMetricGrid {
    static let hostWidth: CGFloat = 345
    static let shellHorizontalInset: CGFloat = 15
    static let blockHorizontalInset: CGFloat = 12
    static let columnCount = 4
    static let columnSpacing: CGFloat = 4

    /// Width available to rows inside `.menuBlock()` (matches `StatusMenuView.menuWidth` insets).
    static var rowWidth: CGFloat {
        hostWidth - shellHorizontalInset * 2 - blockHorizontalInset * 2
    }

    static var columnWidth: CGFloat {
        let gaps = columnSpacing * CGFloat(columnCount - 1)
        return (rowWidth - gaps) / CGFloat(columnCount)
    }

    static func spanWidth(columns: Int) -> CGFloat {
        let count = CGFloat(columns)
        return columnWidth * count + columnSpacing * max(0, count - 1)
    }

    static var threeColumnWidth: CGFloat {
        let gaps = columnSpacing * 2
        return (rowWidth - gaps) / 3
    }

    static var twoColumnWidth: CGFloat {
        let gaps = columnSpacing
        return (rowWidth - gaps) / 2
    }
}

struct MenuSectionHeader: View {
    var title: String
    var iconName: String

    var body: some View {
        Label {
            Text(title.localized())
                .font(.system(size: 12, weight: .bold))
        } icon: {
            Image(iconName)
                .resizable()
                .renderingMode(.template)
                .frame(width: 13, height: 13)
        }
        .labelStyle(.titleAndIcon)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(title.localized())
    }
}

struct MiniSectionView: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.localized())
                .miniSection()
            Text(value)
                .displayText()
        }
        .metricAccessibility(titleKey: title, value: value)
    }
}

struct CompactMiniSectionRow: View {
    var leftTitle: String?
    var leftValue: String?
    var rightTitle: String?
    var rightValue: String?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let leftTitle, let leftValue {
                MiniSectionView(title: leftTitle, value: leftValue)
            }
            if let rightTitle, let rightValue {
                MiniSectionView(title: rightTitle, value: rightValue)
            }
            Spacer(minLength: 0)
        }
    }
}

struct CompactEqualSectionRow: View {
    var items: [(title: String, value: String)?]
    var spacing: CGFloat = MenuMetricGrid.columnSpacing

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(items.indices, id: \.self) { index in
                cell(items[index])
            }
        }
        .frame(width: MenuMetricGrid.rowWidth, alignment: .leading)
    }

    @ViewBuilder
    private func cell(_ item: (title: String, value: String)?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let item {
                Text(item.title.localized())
                    .miniSection()
                    .lineLimit(1)
                Text(item.value)
                    .displayText()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: MenuMetricGrid.columnWidth, alignment: .leading)
        .accessibilityHidden(item == nil)
        .modifier(OptionalMetricAccessibility(item: item))
    }
}

struct CompactQuadSectionRow: View {
    var c0: (title: String, value: String)?
    var c1: (title: String, value: String)?
    var c2: (title: String, value: String)?
    var c3: (title: String, value: String)?

    var body: some View {
        CompactEqualSectionRow(items: [c0, c1, c2, c3])
    }
}

/// Full `rowWidth` split into two equal columns (disk I/O rates); not aligned to the 4-col grid.
struct CompactTwoEqualSectionRow: View {
    var c0: (title: String, value: String)?
    var c1: (title: String, value: String)?

    var body: some View {
        HStack(alignment: .top, spacing: MenuMetricGrid.columnSpacing) {
            twoColumnCell(c0)
            twoColumnCell(c1)
        }
        .frame(width: MenuMetricGrid.rowWidth, alignment: .leading)
    }

    @ViewBuilder
    private func twoColumnCell(_ item: (title: String, value: String)?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let item {
                Text(item.title.localized())
                    .miniSection()
                    .lineLimit(1)
                Text(item.value)
                    .displayText()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: MenuMetricGrid.twoColumnWidth, alignment: .leading)
        .accessibilityHidden(item == nil)
        .modifier(OptionalMetricAccessibility(item: item))
    }
}

/// Full `rowWidth` split into three equal columns (memory header stats); not aligned to the 4-col grid.
struct CompactThreeEqualSectionRow: View {
    var c0: (title: String, value: String)?
    var c1: (title: String, value: String)?
    var c2: (title: String, value: String)?

    var body: some View {
        HStack(alignment: .top, spacing: MenuMetricGrid.columnSpacing) {
            threeColumnCell(c0)
            threeColumnCell(c1)
            threeColumnCell(c2)
        }
        .frame(width: MenuMetricGrid.rowWidth, alignment: .leading)
    }

    @ViewBuilder
    private func threeColumnCell(_ item: (title: String, value: String)?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let item {
                Text(item.title.localized())
                    .miniSection()
                    .lineLimit(1)
                Text(item.value)
                    .displayText()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: MenuMetricGrid.threeColumnWidth, alignment: .leading)
        .accessibilityHidden(item == nil)
        .modifier(OptionalMetricAccessibility(item: item))
    }
}

struct OptionalMetricAccessibility: ViewModifier {
    var item: (title: String, value: String)?

    func body(content: Content) -> some View {
        Group {
            if let item = item {
                content.metricAccessibility(titleKey: item.title, value: item.value)
            } else {
                content
            }
        }
    }
}
