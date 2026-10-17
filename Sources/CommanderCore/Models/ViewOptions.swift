// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

public enum PaneID: String, Codable, Sendable, CaseIterable { case left, right
    public var opposite: PaneID { self == .left ? .right : .left }
}
public enum OpenDestination: String, Codable, Sendable, CaseIterable { case current, left, right }
public enum SortColumn: String, Codable, Sendable { case name, size, modified, kind }
public enum BrowserViewMode: String, Codable, Sendable { case list, icons }
public struct ViewOptions: Codable, Equatable, Sendable {
    public var sortColumn: SortColumn = .name
    public var ascending = true
    public var foldersFirst = true
    public var includeHidden = false
    public var visibleColumns = ["name", "size", "modified"]
    public var textSize: Double = 13
    public var listIconSize: Double = 20
    public var gridIconSize: Double = 64
    public var mode: BrowserViewMode = .list
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case sortColumn, ascending, foldersFirst, includeHidden, visibleColumns, textSize, listIconSize, gridIconSize, mode
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sortColumn = try values.decodeIfPresent(SortColumn.self, forKey: .sortColumn) ?? .name
        ascending = try values.decodeIfPresent(Bool.self, forKey: .ascending) ?? true
        foldersFirst = try values.decodeIfPresent(Bool.self, forKey: .foldersFirst) ?? true
        includeHidden = try values.decodeIfPresent(Bool.self, forKey: .includeHidden) ?? false
        visibleColumns = try values.decodeIfPresent([String].self, forKey: .visibleColumns) ?? ["name", "size", "modified"]
        textSize = try values.decodeIfPresent(Double.self, forKey: .textSize) ?? 13
        listIconSize = try values.decodeIfPresent(Double.self, forKey: .listIconSize) ?? 20
        gridIconSize = try values.decodeIfPresent(Double.self, forKey: .gridIconSize) ?? 64
        mode = try values.decodeIfPresent(BrowserViewMode.self, forKey: .mode) ?? .list
        self = validated()
    }
    public func validated() -> ViewOptions {
        var result = self
        result.textSize = min(20, max(11, textSize.isFinite ? textSize : 13))
        result.listIconSize = min(32, max(16, listIconSize.isFinite ? listIconSize : 20))
        result.gridIconSize = min(128, max(32, gridIconSize.isFinite ? gridIconSize : 64))
        if !result.visibleColumns.contains("name") { result.visibleColumns.insert("name", at: 0) }
        return result
    }
}
public enum TabPin: Codable, Equatable, Sendable {
    case none, locked(home: FileLocation), navigable(home: FileLocation)
    public var home: FileLocation? { switch self { case .none: nil; case .locked(let home), .navigable(let home): home } }
    public var isLocked: Bool { if case .locked = self { true } else { false } }
    public var isPinned: Bool { home != nil }
}
public struct NavigationTicket: Sendable {
    public let tabID: UUID
    public let generation: UInt64
    public let location: FileLocation
}
public struct NavigationTarget: Sendable {
    public let paneID: PaneID
    public let tabID: UUID
    public let ticket: NavigationTicket
    public var location: FileLocation { ticket.location }
    public init(paneID: PaneID, tabID: UUID, ticket: NavigationTicket) {
        self.paneID = paneID; self.tabID = tabID; self.ticket = ticket
    }
}
