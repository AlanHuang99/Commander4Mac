// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import SwiftUI
import CommanderCore

struct AppearanceSettingsView: View {
    @Bindable var services = AppServices.shared
    @Environment(\.colorScheme) private var scheme
    private var style: Binding<ViewAppearance> {
        Binding(get: { services.preferences.view.viewAppearance }, set: { services.updateAppearance($0) })
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Appearance", selection: $services.preferences.appearance) {
                    Text("System").tag(AppearanceMode.system); Text("Light").tag(AppearanceMode.light); Text("Dark").tag(AppearanceMode.dark)
                }.pickerStyle(.segmented)
                HStack(spacing: 10) {
                    ForEach(ThemeID.allCases, id: \.self) { theme in
                        Button { services.preferences.theme = theme } label: {
                            ThemeSwatch(theme: theme, selected: services.preferences.theme == theme, isDark: scheme == .dark)
                        }.buttonStyle(.plain).accessibilityLabel(theme.title + " theme")
                            .accessibilityAddTraits(services.preferences.theme == theme ? .isSelected : [])
                            .accessibilityIdentifier("appearance.theme." + theme.rawValue)
                    }
                }
                AppearanceSharingToggle(shared: $services.preferences.shareAppearanceChanges, prefix: "appearance")
                HStack(alignment: .top, spacing: 18) {
                    GroupBox("Files") { FileAppearanceControls(appearance: style, prefix: "appearance").padding(10) }
                    GroupBox("Navigation") {
                        VStack(spacing: 13) {
                            NavigationAppearanceControls(appearance: style, prefix: "appearance")
                            AppearanceSizeControl(title: "Sidebar width", value: $services.preferences.sidebarWidth, range: 180...320, step: 10, identifier: "appearance.sidebarWidth")
                        }.padding(10)
                    }
                }
                AppearancePreview(appearance: style.wrappedValue, theme: services.preferences.theme, isDark: scheme == .dark)
                HStack {
                    Text("Navigation includes paths, filters and tabs. The sidebar uses your app defaults.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset Appearance") { services.resetAppearance() }.accessibilityIdentifier("appearance.reset")
                }
            }.padding(24)
        }
    }
}

private struct ThemeSwatch: View {
    let theme: ThemeID
    let selected: Bool
    let isDark: Bool
    private var palette: ThemePalette? { theme.palette(isDark: isDark) }
    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 0) {
                (palette?.chrome.color ?? Color(nsColor: .windowBackgroundColor))
                (palette?.accent.color ?? .accentColor)
                (palette?.background.color ?? Color(nsColor: .textBackgroundColor))
            }.frame(height: 40).clipShape(RoundedRectangle(cornerRadius: 7))
            HStack(spacing: 4) {
                Text(theme.title).font(.callout)
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).font(.caption) }
            }
        }.padding(7).frame(maxWidth: .infinity)
            .background(selected ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
    }
}

private struct AppearancePreview: View {
    let appearance: ViewAppearance
    let theme: ThemeID
    let isDark: Bool
    var body: some View {
        let palette = theme.palette(isDark: isDark)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "chevron.left").font(.system(size: appearance.navigationIconSize))
                Image(systemName: "arrow.up").font(.system(size: appearance.navigationIconSize))
                Text("Projects / Design").font(Font(AppearanceFont.resolve(appearance.navigationFont, size: appearance.navigationTextSize)))
            }.foregroundStyle(palette?.secondaryText.color ?? .secondary)
            HStack(spacing: 9) {
                Image(systemName: "folder.fill").font(.system(size: appearance.listIconSize)).foregroundStyle(palette?.accent.color ?? .accentColor)
                Text("Project notes").font(Font(AppearanceFont.resolve(appearance.font, size: appearance.textSize)))
            }.foregroundStyle(palette?.text.color ?? .primary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(palette?.background.color ?? Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1)))
            .accessibilityElement(children: .combine).accessibilityLabel("Appearance preview")
    }
}
