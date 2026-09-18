//
//  View.swift
//  SharedLibrary
//
//  Created by Gao Sun on 2020/11/4.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import AppKit
import SwiftUI
import WidgetKit

public extension View {
    func widgetContainerBackground() -> some View {
        modifier(WidgetContainerBackgroundModifier())
    }
}

private struct WidgetContainerBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, macOSApplicationExtension 14.0, *) {
            WidgetContainerBackgroundV14(content: content)
        } else {
            content.background(Color(NSColor.windowBackgroundColor))
        }
    }
}

@available(macOS 14.0, macOSApplicationExtension 14.0, *)
private struct WidgetContainerBackgroundV14<Content: View>: View {
    @Environment(\.widgetContentMargins) private var widgetContentMargins

    var content: Content

    var body: some View {
        content
            .padding(.top, -widgetContentMargins.top)
            .padding(.leading, -widgetContentMargins.leading)
            .padding(.bottom, -widgetContentMargins.bottom)
            .padding(.trailing, -widgetContentMargins.trailing)
            .containerBackground(for: .widget) {
                Color(NSColor.windowBackgroundColor)
            }
    }
}
