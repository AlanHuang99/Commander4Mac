// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import SwiftUI
import CommanderCore

struct FontChoicePicker: View {
    let title: String
    @Binding var choice: FontChoice
    let identifier: String
    var body: some View {
        Picker(title, selection: $choice) {
            ForEach(FontChoice.presets, id: \.self) { Text($0.title).tag($0) }
            Divider()
            if case .family(let name) = choice, !AppearanceFont.installedFamilies.contains(name) {
                Text(name + " (using System)").tag(choice)
            }
            ForEach(AppearanceFont.installedFamilies, id: \.self) { Text($0).tag(FontChoice.family($0)) }
        }.accessibilityIdentifier(identifier).pickerStyle(.menu)
    }
}

struct AppearanceSizeControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let identifier: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value)) pt").monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityIdentifier(identifier + ".value")
            }.font(.callout)
            Slider(value: $value, in: range, step: step).labelsHidden()
                .accessibilityLabel(title).accessibilityValue("\(Int(value)) points").accessibilityIdentifier(identifier)
        }
    }
}

struct FileAppearanceControls: View {
    @Binding var appearance: ViewAppearance
    let prefix: String
    var body: some View {
        VStack(spacing: 13) {
            FontChoicePicker(title: "Font", choice: $appearance.font, identifier: prefix + ".font")
            AppearanceSizeControl(title: "Text size", value: $appearance.textSize, range: 10...28, identifier: prefix + ".textSize")
            AppearanceSizeControl(title: "List icons", value: $appearance.listIconSize, range: 12...40, step: 2, identifier: prefix + ".listIcons")
            AppearanceSizeControl(title: "Grid icons", value: $appearance.gridIconSize, range: 32...160, step: 8, identifier: prefix + ".gridIcons")
        }
    }
}

struct NavigationAppearanceControls: View {
    @Binding var appearance: ViewAppearance
    let prefix: String
    var body: some View {
        VStack(spacing: 13) {
            FontChoicePicker(title: "Font", choice: $appearance.navigationFont, identifier: prefix + ".navigationFont")
            AppearanceSizeControl(title: "Navigation text", value: $appearance.navigationTextSize, range: 10...24, identifier: prefix + ".navigationText")
            AppearanceSizeControl(title: "Navigation icons", value: $appearance.navigationIconSize, range: 12...28, identifier: prefix + ".navigationIcons")
        }
    }
}

struct AppearanceSharingToggle: View {
    @Binding var shared: Bool
    let prefix: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle("Apply appearance changes to all tabs and panes", isOn: $shared)
                .toggleStyle(.checkbox).accessibilityIdentifier(prefix + ".share")
            Text(shared ? "Updates existing and new tabs, panes, and windows." : "Pane changes stay in that tab. Settings define defaults for new tabs.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
