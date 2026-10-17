// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
import Observation

@MainActor @Observable
public final class TabSession: Identifiable {
    @ObservationIgnored public var loadStartedAt: TimeInterval = 0
    @ObservationIgnored public var switchStartedAt: TimeInterval?
    public let id: UUID
    public private(set) var location: FileLocation
    public var pin: TabPin = .none
    public var selection: Set<EntryID> = []
    public var unresolvedReference: LocationReference?
    public var savedReference: LocationReference?
    public var scrollAnchor: EntryID?
    public var filter = "" { didSet { rebuildVisibleEntries() } }
    public var options: ViewOptions {
        didSet {
            if oldValue.sortColumn != options.sortColumn || oldValue.ascending != options.ascending || oldValue.foldersFirst != options.foldersFirst || oldValue.includeHidden != options.includeHidden { rebuildVisibleEntries() }
        }
    }
    public private(set) var snapshot: DirectorySnapshot?
    public private(set) var entriesRevision: UInt64 = 0
    // Notify via entriesRevision so Observation does not compare every file on the main thread.
    @ObservationIgnored public private(set) var visibleEntries: [FileEntry] = []
    public private(set) var isLoading = false
    public private(set) var failure: FileFailure?
    public private(set) var generation: UInt64 = 0
    public private(set) var history: [FileLocation]
    public private(set) var historyIndex = 0
    public var title: String { (pin.home ?? location).title }
    public var selectedEntries: [FileEntry] { visibleEntries.filter { selection.contains($0.id) } }
    public var canGoBack: Bool { historyIndex > 0 }
    public var canGoForward: Bool { historyIndex + 1 < history.count }
    public init(id: UUID = UUID(), location: FileLocation, options: ViewOptions = .init()) {
        self.id = id; self.location = location; self.options = options.validated(); history = [location]
    }
    public func restoreHistory(_ locations: [FileLocation], index: Int) {
        guard locations.indices.contains(index), locations[index] == location else { return }
        history = locations; historyIndex = index
    }
    @discardableResult public func requestNavigation(to location: FileLocation) -> NavigationTicket {
        unresolvedReference = nil
        if self.location != location {
            history = Array(history.prefix(historyIndex + 1)); history.append(location); historyIndex = history.count - 1
        }
        return begin(location)
    }
    private func begin(_ location: FileLocation) -> NavigationTicket {
        if self.location != location { snapshot = nil; visibleEntries = []; entriesRevision &+= 1; selection = []; filter = ""; scrollAnchor = nil; savedReference = nil; unresolvedReference = nil }
        loadStartedAt = ProcessInfo.processInfo.systemUptime
        self.location = location; generation &+= 1; isLoading = true; failure = nil
        return NavigationTicket(tabID: id, generation: generation, location: location)
    }
    @discardableResult public func apply(_ snapshot: DirectorySnapshot, for ticket: NavigationTicket) -> Bool {
        guard ticket.tabID == id, ticket.generation == generation, ticket.location == location, snapshot.location == location else { return false }
        if let previous = self.snapshot {
            let newIDs = Set(snapshot.entries.map(\.id))
            let oldGroups = Dictionary(grouping: previous.entries.filter { $0.fileIdentity != nil }, by: { $0.fileIdentity! })
            let newGroups = Dictionary(grouping: snapshot.entries.filter { $0.fileIdentity != nil }, by: { $0.fileIdentity! })
            var replacements: [EntryID: EntryID] = [:]
            for (identity, old) in oldGroups where old.count == 1 && !newIDs.contains(old[0].id) {
                if let new = newGroups[identity], new.count == 1 { replacements[old[0].id] = new[0].id }
            }
            selection = Set(selection.map { replacements[$0] ?? $0 })
            if let anchor = scrollAnchor { scrollAnchor = replacements[anchor] ?? anchor }
        }
        self.snapshot = snapshot; isLoading = false; failure = nil; rebuildVisibleEntries(); return true
    }
    @discardableResult public func fail(_ error: Error, for ticket: NavigationTicket) -> Bool {
        guard ticket.tabID == id, ticket.generation == generation else { return false }
        failure = (error as? FileFailure) ?? FileFailure(error, at: location)
        isLoading = false; snapshot = nil; visibleEntries = []; entriesRevision &+= 1; return true
    }
    public func goBack() -> NavigationTicket? {
        guard canGoBack else { return nil }; historyIndex -= 1; return begin(history[historyIndex])
    }
    public func goForward() -> NavigationTicket? {
        guard canGoForward else { return nil }; historyIndex += 1; return begin(history[historyIndex])
    }
    private func rebuildVisibleEntries() {
        let options = options
        var rows = snapshot?.entries ?? []
        if !filter.isEmpty { rows = rows.filter { $0.name.localizedStandardContains(filter) } }
        rows.sort { a, b in
            if options.foldersFirst && a.isDirectory != b.isDirectory { return a.isDirectory }
            let order: ComparisonResult
            switch options.sortColumn {
            case .name: order = a.name.localizedStandardCompare(b.name)
            case .size:
                if a.byteSize == b.byteSize { order = a.name.localizedStandardCompare(b.name) }
                else { order = (a.byteSize ?? -1) < (b.byteSize ?? -1) ? .orderedAscending : .orderedDescending }
            case .modified:
                if a.modificationDate == b.modificationDate { order = a.name.localizedStandardCompare(b.name) }
                else { order = (a.modificationDate ?? .distantPast) < (b.modificationDate ?? .distantPast) ? .orderedAscending : .orderedDescending }
            case .kind: order = a.kind.rawValue == b.kind.rawValue ? a.name.localizedStandardCompare(b.name) : a.kind.rawValue.compare(b.kind.rawValue)
            }
            return options.ascending ? order == .orderedAscending : order == .orderedDescending
        }
        entriesRevision &+= 1
        visibleEntries = rows
        selection.formIntersection(Set(rows.map(\.id)))
    }
}
