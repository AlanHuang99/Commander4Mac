// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

public struct SavedApplicationState: Codable, Sendable {
    public var version = 1
    public var windows: [WorkspaceSnapshot]
    public var favorites: [Favorite]
    public var shelf: [StagedItem]
    public init(windows: [WorkspaceSnapshot] = [], favorites: [Favorite] = [], shelf: [StagedItem] = []) {
        self.windows = windows; self.favorites = favorites; self.shelf = shelf
    }
}
public struct StateLoadResult: Sendable {
    public let state: SavedApplicationState
    public let diagnostic: String?
}
public struct ApplicationStateStore: Sendable {
    public let fileURL: URL
    public init(directory: URL) { fileURL = directory.appendingPathComponent("session.json") }
    public func save(_ state: SavedApplicationState) throws { try AtomicFileWriter.write(JSONEncoder().encode(state), to: fileURL) }
    public func loadRecovering() -> StateLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .init(state: .init(), diagnostic: nil) }
        do {
            let state = try JSONDecoder().decode(SavedApplicationState.self, from: Data(contentsOf: fileURL))
            guard state.version == 1 else { throw CocoaError(.coderReadCorrupt) }
            return .init(state: state, diagnostic: nil)
        } catch {
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("session-corrupt-" + UUID().uuidString + ".json")
            do { try FileManager.default.copyItem(at: fileURL, to: backup) }
            catch { return .init(state: .init(), diagnostic: "Could not read or preserve the previous session: \(error.localizedDescription)") }
            return .init(state: .init(), diagnostic: "The previous session was unreadable and has been preserved at \(backup.path).")
        }
    }
}
public struct TabSnapshot: Codable, Sendable {
    let id: UUID
    var reference: LocationReference
    let pin: TabPin
    let options: ViewOptions
    let selection: Set<EntryID>
    let scrollAnchor: EntryID?
    let filter: String
    let history: [FileLocation]
    let historyIndex: Int
    // Save-only values. They are not serialized and never perform filesystem work.
    var remoteLocation: FileLocation? = nil
    var referenceLocation: FileLocation? = nil
    var capturedGeneration: UInt64? = nil
    enum CodingKeys: String, CodingKey { case id, reference, pin, options, selection, scrollAnchor, filter, history, historyIndex, remoteLocation }
    @MainActor init(_ tab: TabSession) throws {
        id = tab.id
        let displayURL: URL
        switch tab.location { case .local(let url): displayURL = url; case .sftp, .smb, .webdav: displayURL = tab.location.url; remoteLocation = tab.location }
        reference = tab.unresolvedReference ?? tab.savedReference ??
            LocationReference(bookmark: Data(), displayURL: displayURL, expectedIdentity: .init(device: 0, inode: 0))
        pin = tab.pin; options = tab.options; selection = tab.selection; scrollAnchor = tab.scrollAnchor
        filter = tab.filter; history = tab.history; historyIndex = tab.historyIndex
        referenceLocation = tab.unresolvedReference == nil && tab.location.isLocal ? tab.location : nil
        capturedGeneration = tab.generation
    }
    @MainActor func restore() -> TabSession {
        // Resolve lazily on a bounded worker when the tab is activated.
        let tab = TabSession(id: id, location: remoteLocation ?? .local(reference.displayURL), options: options)
        tab.pin = pin; tab.filter = filter; tab.selection = selection; tab.scrollAnchor = scrollAnchor
        tab.restoreHistory(history, index: historyIndex)
        if remoteLocation == nil { tab.unresolvedReference = reference }
        return tab
    }
    mutating func refreshReference(using resolver: any LocationResolving) {
        if let referenceLocation, let refreshed = try? resolver.reference(for: referenceLocation) { reference = refreshed }
    }
    @MainActor func applyReference(to tab: TabSession) {
        guard referenceLocation != nil, tab.generation == capturedGeneration,
              tab.unresolvedReference == nil, !reference.bookmark.isEmpty else { return }
        tab.savedReference = reference
    }
}
public struct PaneSnapshot: Codable, Sendable {
    var tabs: [TabSnapshot]
    let activeTabID: UUID
    @MainActor init(_ pane: PaneSession) throws { tabs = try pane.tabs.map(TabSnapshot.init); activeTabID = pane.activeTabID }
    @MainActor func restore() -> PaneSession {
        let restored = tabs.map { $0.restore() }
        let pane = PaneSession(location: restored.first?.location ?? .local(FileManager.default.homeDirectoryForCurrentUser))
        if !restored.isEmpty { pane.tabs = restored }
        pane.activeTabID = pane.tabs.contains { $0.id == activeTabID } ? activeTabID : pane.tabs[0].id
        return pane
    }
}
public struct WorkspaceSnapshot: Codable, Sendable {
    let id: UUID
    var left: PaneSnapshot
    var right: PaneSnapshot
    let activePane: PaneID
    var splitRatio: Double? = nil
    @MainActor public init(_ workspace: WorkspaceSession) throws {
        id = workspace.id; left = try PaneSnapshot(workspace.left); right = try PaneSnapshot(workspace.right); activePane = workspace.activePane; splitRatio = workspace.splitRatio
    }
    @MainActor public func restore() -> WorkspaceSession {
        let workspace = WorkspaceSession(id: id)
        workspace.left = left.restore(); workspace.right = right.restore(); workspace.activePane = activePane; workspace.splitRatio = min(0.8, max(0.2, splitRatio ?? 0.5))
        return workspace
    }
    mutating func refreshReferences(using resolver: any LocationResolving) {
        for index in left.tabs.indices { left.tabs[index].refreshReference(using: resolver) }
        for index in right.tabs.indices { right.tabs[index].refreshReference(using: resolver) }
    }
    @MainActor public func applyReferences(to workspace: WorkspaceSession) {
        guard id == workspace.id else { return }
        for (saved, pane) in [(left, workspace.left), (right, workspace.right)] {
            for snapshot in saved.tabs {
                if let tab = pane.tabs.first(where: { $0.id == snapshot.id }) { snapshot.applyReference(to: tab) }
            }
        }
    }
}

/// Serializes background reference creation and writes, including superseded save requests.
public actor SessionPersistence {
    private let store: ApplicationStateStore
    private let resolver: any LocationResolving
    private let gate = OperationGate()
    private var lastSavedRevision: UInt64 = 0
    public init(store: ApplicationStateStore, resolver: any LocationResolving = LocationResolver()) {
        self.store = store; self.resolver = resolver
    }
    public func save(_ state: SavedApplicationState, revision: UInt64) async throws -> SavedApplicationState? {
        await gate.acquire()
        guard revision > lastSavedRevision else { await gate.release(); return nil }
        do {
            let store = store; let resolver = resolver
            let saved = try await BlockingFileWorker.run {
                var state = state
                for index in state.windows.indices { state.windows[index].refreshReferences(using: resolver) }
                try store.save(state)
                return state
            }
            lastSavedRevision = revision
            await gate.release()
            return saved
        } catch { await gate.release(); throw error }
    }
}
