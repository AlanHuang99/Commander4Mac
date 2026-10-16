import SwiftUI

@main
struct Commander4MacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        WindowGroup("Commander4Mac", id: "workspace") { WorkspaceView() }
            .defaultSize(width: 1240, height: 760)
        Settings { SettingsView() }
    }
}
