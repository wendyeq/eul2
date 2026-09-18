//
//  WidgetSectionView.swift
//  eul
//
//  Created by Gao Sun on 2020/11/4.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import SwiftUI

public struct WidgetSectionView: View {
    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }

    public var title: String
    public var value: String

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.thirdary)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
