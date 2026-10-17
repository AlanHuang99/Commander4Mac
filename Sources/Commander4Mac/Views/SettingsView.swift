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
            AppearanceSettingsView().tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
            UpdateSettingsView().tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            Form {
                ForEach([("Open", "⌘O"), ("Rename", "Return"), ("Quick Look", "Space"), ("Switch Pane", "Tab"),
                         ("Copy to Other Pane", "F5"), ("Move to Other Pane", "F6"), ("New Folder", "F7"),
                         ("Move to Trash", "⌘Delete"), ("Edit Path", "⌘L"), ("New Tab", "⌘T")], id: \.0) { name, shortcut in
                    LabeledContent(name) { Text(shortcut).foregroundStyle(.secondary) }
                }
            }.padding(24).tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }.frame(width: 660, height: 620)
        .preferredColorScheme(services.preferences.appearance.colorScheme)
        .sheet(isPresented: $showAccess) { AccessSetupView { showAccess = false } }
    }
}
