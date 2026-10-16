import SwiftUI

@main
struct Commander4MacApp: App {
    @AppStorage("accessSetupAcknowledged") private var acknowledged = false
    var body: some Scene {
        WindowGroup("Commander4Mac", id: "workspace") {
            VStack(spacing: 20) {
                Image(systemName: "rectangle.split.2x1").font(.system(size: 42))
                Text("Commander4Mac").font(.largeTitle)
                Text("Your local workspace").foregroundStyle(.secondary)
                Button("Full Disk Access Setup") { acknowledged = false }
            }
            .frame(minWidth: 1000, minHeight: 650)
            .sheet(isPresented: Binding(get: { !acknowledged }, set: { if !$0 { acknowledged = true } })) {
                AccessSetupView { acknowledged = true }
            }
        }
        Settings { Text("Commander4Mac Settings").padding(30) }
    }
}
