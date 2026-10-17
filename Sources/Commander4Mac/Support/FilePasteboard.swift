// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import AppKit
import CommanderCore

@MainActor enum FilePasteboard {
    static func readLocations(from pasteboard: NSPasteboard = .general) -> [FileLocation] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return FileDropRequest.locations(from: urls.map(\.absoluteString))
    }
    static func write(_ locations: [FileLocation]) {
        guard !locations.isEmpty, locations.allSatisfy(\.isLocal) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(locations.map { $0.url as NSURL })
    }
}
