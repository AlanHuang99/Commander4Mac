import SwiftUI

@main
struct Commander4MacApp: App {
    var body: some Scene {
        WindowGroup("Commander4Mac", id: "workspace") { WorkspaceView() }
            .defaultSize(width: 1240, height: 760)
        Settings { Text("Commander4Mac Settings").padding(30) }
    }
}
