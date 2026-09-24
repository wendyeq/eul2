//
//  PreferenceFormControls.swift
//  eul
//
//  System Settings–like inset rows: leading label, trailing control.
//

import SwiftUI

struct PreferenceInsetFormGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background {
            RoundedRectangle(cornerRadius: PreferenceChrome.groupedRowCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: PreferenceChrome.groupedRowCornerRadius, style: .continuous)
                .strokeBorder(Color.separator.opacity(0.55), lineWidth: 1)
        }
        .frame(maxWidth: PreferenceChrome.detailContentWidth, alignment: .leading)
    }
}

struct PreferenceFormRowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.separator.opacity(0.45))
            .frame(height: 1)
            .padding(.leading, PreferenceChrome.formRowInsetHorizontal)
    }
}

struct PreferenceFormSplitRow<Label: View, Control: View>: View {
    var showsDivider: Bool
    var trailingSlotWidth: CGFloat = PreferenceChrome.formTrailingSwitchSlotWidth
    var singleLineLabel = true
    @ViewBuilder var label: () -> Label
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                label()
                    .lineLimit(singleLineLabel ? 1 : nil)
                    .fixedSize(horizontal: singleLineLabel, vertical: false)
                Spacer(minLength: 4)
                control()
                    .frame(width: trailingSlotWidth, alignment: .trailing)
            }
            .padding(.horizontal, PreferenceChrome.formRowInsetHorizontal)
            .padding(.vertical, PreferenceChrome.formRowInsetVertical)
            .frame(minHeight: PreferenceChrome.formControlRowMinHeight)
            if showsDivider {
                PreferenceFormRowSeparator()
            }
        }
    }
}

struct PreferenceFormSwitchRow: View {
    let title: String
    @Binding var isOn: Bool
    var showsDivider: Bool = true
    var disabled: Bool = false

    var body: some View {
        PreferenceFormSplitRow(
            showsDivider: showsDivider,
            trailingSlotWidth: PreferenceChrome.formTrailingSwitchSlotWidth
        ) {
            Text(title)
                .preferenceFormLabel()
        } control: {
            Toggle("", isOn: $isOn)
                .preferenceFormTrailingSwitch()
                .disabled(disabled)
        }
    }
}

struct PreferenceFormPickerRow<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    var showsDivider: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        PreferenceFormSplitRow(
            showsDivider: showsDivider,
            trailingSlotWidth: PreferenceChrome.formTrailingPickerSlotWidth
        ) {
            Text(title)
                .preferenceFormLabel()
        } control: {
            Picker("", selection: $selection, content: content)
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
