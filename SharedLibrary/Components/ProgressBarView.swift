//
//  ProgressBarView.swift
//  eul
//
//  Created by Gao Sun on 2020/9/20.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import AppKit
import SwiftUI

public struct ProgressBarView: View {
    public init(
        width: CGFloat = 80,
        percentage: CGFloat = 100,
        showText: Bool = true,
        textWidth: CGFloat = 40,
        customText: String? = nil,
        glassTrack: Bool = false
    ) {
        self.width = width
        self.percentage = percentage
        self.showText = showText
        self.textWidth = textWidth
        self.customText = customText
        self.glassTrack = glassTrack
    }

    @State var firstAppear = true
    public var width: CGFloat = 80
    public var percentage: CGFloat = 100
    public var showText = true
    public var textWidth: CGFloat = 40
    public var customText: String?
    public var glassTrack = false

    private var trackColor: Color {
        if glassTrack {
            return Color.separator.opacity(increaseContrast ? 0.65 : 0.4)
        }
        return .controlBackground
    }

    private var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    private var barHeight: CGFloat {
        increaseContrast ? 6 : 4
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .frame(width: width, height: barHeight)
                    .foregroundColor(trackColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.separator.opacity(increaseContrast ? 0.9 : 0), lineWidth: 1)
                    )
                RoundedRectangle(cornerRadius: 4)
                    .frame(width: width * percentage / 100, height: barHeight)
                    .foregroundColor(.primary)
            }
            if showText {
                Text(customText.map { $0 } ?? String(format: "%.1f%%", percentage))
                    .displayText()
                    .frame(width: textWidth, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(customText ?? String(format: "%.0f%%", Double(percentage)))
        .onAppear {
            self.firstAppear = false
        }
    }
}
