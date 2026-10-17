// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import SwiftUI
import CommanderCore

struct ConflictSheet: View {
    let conflict: TransferConflict
    var resolve: (ConflictResolution) -> Void
    @State private var applyToAll = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("An item already exists", systemImage: "doc.on.doc").font(.title2).fontWeight(.semibold)
            Text(conflict.destination.lastPathComponent).fontWeight(.semibold).textSelection(.enabled)
            VStack(alignment: .leading, spacing: 6) {
                Text("From: \(conflict.source.url.path)")
                Text("To: \(conflict.destination.path)")
            }.font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            if conflict.isDirectory { Text("Replace replaces the entire destination folder, including its existing contents.").font(.callout) }
            Toggle("Apply to remaining conflicts in this job", isOn: $applyToAll)
            HStack {
                Button("Cancel Job", role: .cancel) { resolve(.init(.cancel)) }
                Spacer()
                Button("Skip") { resolve(.init(.skip, applyToAll: applyToAll)) }
                Button("Keep Both") { resolve(.init(.keepBoth, applyToAll: applyToAll)) }.keyboardShortcut(.defaultAction)
                if conflict.supportsReplacement { Button("Replace", role: .destructive) { resolve(.init(.replace, applyToAll: applyToAll)) } }
            }
        }.padding(24).frame(width: 560).interactiveDismissDisabled()
    }
}
