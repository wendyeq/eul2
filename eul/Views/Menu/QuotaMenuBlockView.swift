//
//  QuotaMenuBlockView.swift
//  eul
//

import Localize_Swift
import SharedLibrary
import SwiftUI

struct QuotaMenuBlockView: View {
    @EnvironmentObject var quotaStore: QuotaStore
    @EnvironmentObject var preferenceStore: PreferenceStore
    @Environment(\.menuCompactLayout) private var menuCompactLayout

    private var visibleProviders: [Preference.QuotaProvider] {
        preferenceStore.orderedQuotaProviders.filter(preferenceStore.isQuotaProviderVisible)
    }

    var body: some View {
        if !visibleProviders.isEmpty {
            VStack(alignment: .leading, spacing: menuCompactLayout ? MenuExpandedLayout.sectionSpacing : 8) {
                MenuSectionHeader(title: "component.quota", iconName: "Quota")
                ForEach(visibleProviders) { provider in
                    providerMeters(provider)
                }
            }
            .menuBlock()
        }
    }

    private func snapshot(for provider: Preference.QuotaProvider) -> QuotaProviderSnapshot {
        switch provider {
        case .cursor:
            return quotaStore.cursor
        case .grok:
            return quotaStore.grok
        case .codex:
            return quotaStore.codex
        }
    }

    @ViewBuilder
    private func providerMeters(_ provider: Preference.QuotaProvider) -> some View {
        let snapshot = snapshot(for: provider)
        let title = provider.titleKey.localized()
        switch snapshot.kind {
        case .pending:
            EmptyView()
        case .unsigned:
            QuotaStatusRow(title: title, message: provider.signInKey.localized())
        case .failed where snapshot.meters.isEmpty:
            QuotaStatusRow(title: title, message: "quota.failed".localized())
        case .ready where snapshot.meters.isEmpty:
            QuotaStatusRow(title: title, message: "ui.empty".localized())
        case .ready, .failed:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.meters, id: \.id) { meter in
                    QuotaMeterRow(
                        title: "\(title) · \(meter.labelKey.localized())",
                        meter: meter
                    )
                }
                if snapshot.kind == .failed {
                    Text("quota.failed".localized())
                        .secondaryDisplayText()
                }
            }
        }
    }
}

private struct QuotaStatusRow: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Text(message)
                .secondaryDisplayText()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .frame(width: MenuMetricGrid.rowWidth, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(message)
    }
}

private struct QuotaMeterRow: View {
    let title: String
    let meter: QuotaMeter

    private var percentText: String {
        let value = meter.usedPercent
        if abs(value - value.rounded()) < 0.05 {
            return String(format: "%.0f%%", value)
        }
        return String(format: "%.1f%%", value)
    }

    private var countdown: String {
        QuotaCountdown.text(resetsAt: meter.resetsAt)
    }

    private var elapsedPercent: Double? {
        QuotaWindowElapsed.percent(start: meter.windowStart, end: meter.resetsAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(percentText)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                Spacer(minLength: 8)
                if !countdown.isEmpty {
                    Text(countdown)
                        .secondaryDisplayText()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            QuotaUsageBar(percent: meter.usedPercent, elapsedPercent: elapsedPercent)
        }
        .frame(width: MenuMetricGrid.rowWidth, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var parts = [percentText]
        if !countdown.isEmpty {
            parts.append(countdown)
        }
        if let elapsedPercent {
            parts.append(String(format: "quota.window_elapsed".localized(), String(format: "%.0f%%", elapsedPercent)))
        }
        return parts.joined(separator: ", ")
    }
}

/// Usage fill = subscription used. Vertical tick = how far the reset window has elapsed.
private struct QuotaUsageBar: View {
    var percent: Double
    var elapsedPercent: Double?

    private let trackHeight: CGFloat = 8
    private let tickWidth: CGFloat = 1.5
    private let tickHeight: CGFloat = 12

    private var fillWidth: CGFloat {
        let clamped = CGFloat(QuotaTimestamp.clampPercent(percent))
        let width = MenuMetricGrid.rowWidth * clamped / 100
        if clamped > 0, width < 2 {
            return 2
        }
        return width
    }

    private var tickOffset: CGFloat {
        guard let elapsedPercent else {
            return 0
        }
        let x = MenuMetricGrid.rowWidth * CGFloat(QuotaTimestamp.clampPercent(elapsedPercent)) / 100
        return min(MenuMetricGrid.rowWidth - tickWidth, max(0, x - tickWidth / 2))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.12))
                .frame(height: trackHeight)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary)
                .frame(width: fillWidth, height: trackHeight)
            if elapsedPercent != nil {
                Capsule()
                    .fill(Color.primary)
                    .frame(width: tickWidth, height: tickHeight)
                    .offset(x: tickOffset)
            }
        }
        .frame(width: MenuMetricGrid.rowWidth, height: tickHeight)
        .accessibilityHidden(true)
    }
}
