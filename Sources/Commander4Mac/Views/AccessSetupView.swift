import SwiftUI
import AppKit

struct AccessSetupView: View {
    var onContinue: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Full Disk Access", systemImage: "externaldrive.badge.checkmark")
                .font(.title2.weight(.semibold))
            Text("Give Commander4Mac access to your files")
                .font(.headline)
            Text("In System Settings, open Privacy & Security, then Full Disk Access. Add this installed app and enable its switch.")
            Text(RuntimeIdentity.bundleURL.path).font(.callout.monospaced())
                .textSelection(.enabled).padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            Text("After enabling access, restart the app if macOS requests it. Individual files may still have their own permissions.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                }
                Spacer()
                Button("I’ve enabled it") { onContinue() }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 540)
    }
}
