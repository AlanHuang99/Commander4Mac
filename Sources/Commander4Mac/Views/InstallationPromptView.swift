// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import SwiftUI
import AppKit

struct InstallationPromptView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: RuntimeIdentity.bundleURL.path))
                    .resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Move to Applications").font(.title2.weight(.semibold))
                    Text("Give Commander4Mac a permanent home.").foregroundStyle(.secondary)
                }
            }
            Text("Install the app before setting up Full Disk Access. This keeps permission setup tied to the copy you’ll use.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                Text("1. Quit this copy of Commander4Mac.")
                Text("2. Drag the app into the Applications folder.")
                Text("3. Open the app from Applications.")
            }.font(.callout)
            HStack {
                Button("Show This App") { NSWorkspace.shared.activateFileViewerSelecting([RuntimeIdentity.bundleURL]) }
                    .accessibilityIdentifier("installation.reveal")
                Button("Open Applications") { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true)) }
                    .accessibilityIdentifier("installation.applications")
                Spacer()
                Button("Quit This Copy") { NSApp.terminate(nil) }
                    .keyboardShortcut(.defaultAction).accessibilityIdentifier("installation.quit")
            }
        }.padding(28).frame(width: 550)
    }
}
