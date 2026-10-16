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
    let reference: LocationReference
    let pin: TabPin
    let options: ViewOptions
    let selection: Set<EntryID>
    let scrollAnchor: EntryID?
    let filter: String
    let history: [FileLocation]
    let historyIndex: Int
    @MainActor init(_ tab: TabSession) throws {
        id = tab.id
        reference = tab.unresolvedReference ?? (try? LocationResolver().reference(for: tab.location)) ??
            LocationReference(bookmark: Data(), displayURL: tab.location.url, expectedIdentity: .init(device: 0, inode: 0))
        pin = tab.pin; options = tab.options; selection = tab.selection; scrollAnchor = tab.scrollAnchor
        filter = tab.filter; history = tab.history; historyIndex = tab.historyIndex
    }
    @MainActor func restore() -> TabSession {
        let location: FileLocation
        var unresolved = false
        switch LocationResolver().resolve(reference) {
        case .available(let resolved): location = resolved
        case .unavailable, .needsRelink: location = .local(reference.displayURL); unresolved = true
        }
        let tab = TabSession(id: id, location: location, options: options)
        tab.pin = pin; tab.filter = filter; tab.selection = selection; tab.scrollAnchor = scrollAnchor
        tab.restoreHistory(history, index: historyIndex)
        if unresolved { tab.unresolvedReference = reference }
        return tab
    }
}
public struct PaneSnapshot: Codable, Sendable {
    let tabs: [TabSnapshot]
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
    let left: PaneSnapshot
    let right: PaneSnapshot
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
}
