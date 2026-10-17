// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

@MainActor
public final class DirectoryLoader {
    private weak var workspace: WorkspaceSession?
    private let provider: any DirectoryProviding
    public init(workspace: WorkspaceSession, provider: any DirectoryProviding = LocalFileSystem()) {
        self.workspace = workspace; self.provider = provider
    }
    public func load(target: NavigationTarget, options: ListingOptions) async {
        guard let tab = workspace?.pane(target.paneID).tabs.first(where: { $0.id == target.tabID }) else { return }
        do {
            let snapshot = try await provider.list(target.location, options: options)
            guard !Task.isCancelled else { return }
            _ = tab.apply(snapshot, for: target.ticket)
        } catch {
            guard !Task.isCancelled else { return }
            _ = tab.fail(error, for: target.ticket)
        }
    }
}
