//
//  SeparatorView.swift
//  eul
//
//  Created by Gao Sun on 2020/9/20.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import SwiftUI

public struct SeparatorView: View {
    public init(padding: CGFloat = 4, menuSection: Bool = false) {
        self.padding = menuSection ? 2 : padding
        self.menuSection = menuSection
    }

    public var padding: CGFloat = 4
    public var menuSection: Bool = false

    public var body: some View {
        Rectangle()
            .fill(Color.separator.opacity(menuSection ? 0.55 : 1))
            .frame(height: 1)
            .padding(.vertical, padding)
    }
}
