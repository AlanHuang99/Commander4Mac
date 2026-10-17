// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

@MainActor public enum CommandRouter {
    public enum OpenDisposition: Sendable { case browse, systemApplication }
    public static func transfer(_ kind: TransferKind, in workspace: WorkspaceSession, textEditing: Bool) -> TransferRequest? {
        guard !textEditing else { return nil }
        let sources = workspace.activeTab.selectedEntries.map(\.location)
        guard !sources.isEmpty else { return nil }
        return .init(kind: kind, sources: sources, destinationDirectory: workspace.pane(workspace.activePane.opposite).activeTab.location)
    }
    public static func previewItems(in workspace: WorkspaceSession) -> [FileLocation] { workspace.activeTab.selectedEntries.map(\.location).filter(\.isLocal) }
    public static func openDisposition(kind: FileKind) -> OpenDisposition { kind == .directory ? .browse : .systemApplication }
    public static func packageContents(_ location: FileLocation) -> FileLocation { location }
}
