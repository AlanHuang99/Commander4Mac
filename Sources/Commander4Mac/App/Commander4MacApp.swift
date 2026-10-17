// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import SwiftUI

@main
struct Commander4MacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup(RuntimeIdentity.needsInstallation ? "Install Commander4Mac" : "Commander4Mac", id: "workspace") {
            if RuntimeIdentity.needsInstallation { InstallationPromptView() }
            else { WorkspaceView() }
        }
        .defaultSize(width: RuntimeIdentity.needsInstallation ? 606 : 1240, height: RuntimeIdentity.needsInstallation ? 410 : 760)
        .windowResizability(RuntimeIdentity.needsInstallation ? .contentSize : .automatic)
        .commands { AppCommands() }
        Settings {
            if RuntimeIdentity.needsInstallation { InstallationPromptView() }
            else { SettingsView() }
        }
    }
}
