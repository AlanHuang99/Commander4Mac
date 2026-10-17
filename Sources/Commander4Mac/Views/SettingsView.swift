// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import SwiftUI
import CommanderCore

extension AppearanceMode {
    var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}
struct SettingsView: View {
    @Bindable var services = AppServices.shared
    @State private var showAccess = false
    var body: some View {
        TabView {
            Form {
                Toggle("Restore windows and tabs at launch", isOn: $services.preferences.restoreSession)
                Picker("Open favorites and folders in", selection: $services.preferences.defaultDestination) {
                    Text("Current Pane").tag(OpenDestination.current)
                    Text("Left Pane").tag(OpenDestination.left)
                    Text("Right Pane").tag(OpenDestination.right)
                }
                Button("Full Disk Access Setup…") { showAccess = true }
            }.padding(24).tabItem { Label("General", systemImage: "gearshape") }
            Form {
                Picker("Appearance", selection: $services.preferences.appearance) {
                    Text("System").tag(AppearanceMode.system); Text("Light").tag(AppearanceMode.light); Text("Dark").tag(AppearanceMode.dark)
                }.pickerStyle(.segmented)
                Slider(value: $services.preferences.view.textSize, in: 11...20, step: 1) {
                    Text("Text size: \(Int(services.preferences.view.textSize)) pt")
                }.accessibilityLabel("Default text size").accessibilityValue("\(Int(services.preferences.view.textSize)) points")
                Slider(value: $services.preferences.view.listIconSize, in: 16...32, step: 1) {
                    Text("List icons: \(Int(services.preferences.view.listIconSize)) pt")
                }.accessibilityLabel("Default list icon size").accessibilityValue("\(Int(services.preferences.view.listIconSize)) points")
                Slider(value: $services.preferences.view.gridIconSize, in: 32...128, step: 8) {
                    Text("Grid icons: \(Int(services.preferences.view.gridIconSize)) pt")
                }.accessibilityLabel("Default grid icon size").accessibilityValue("\(Int(services.preferences.view.gridIconSize)) points")
                Text("Defaults apply to new tabs. Use a pane’s View Options to change an existing tab.").font(.callout).foregroundStyle(.secondary)
            }.padding(24).tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
            Form {
                ForEach([("Open", "⌘O"), ("Rename", "Return"), ("Quick Look", "Space"), ("Switch Pane", "Tab"),
                         ("Copy to Other Pane", "F5"), ("Move to Other Pane", "F6"), ("New Folder", "F7"),
                         ("Move to Trash", "⌘Delete"), ("Edit Path", "⌘L"), ("New Tab", "⌘T")], id: \.0) { name, shortcut in
                    LabeledContent(name) { Text(shortcut).foregroundStyle(.secondary) }
                }
            }.padding(24).tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }.frame(width: 540, height: 390)
        .preferredColorScheme(services.preferences.appearance.colorScheme)
        .sheet(isPresented: $showAccess) { AccessSetupView { showAccess = false } }
    }
}
