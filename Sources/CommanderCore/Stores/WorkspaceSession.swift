import Foundation
import Observation

@MainActor @Observable
public final class WorkspaceSession: Identifiable {
    public let id: UUID
    public var left: PaneSession
    public var right: PaneSession
    public var activePane: PaneID = .left
    public var splitRatio: Double = 0.5
    public var defaultOptions = ViewOptions()
    public init(id: UUID = UUID(), left: FileLocation = .local(FileManager.default.homeDirectoryForCurrentUser),
                right: FileLocation = .local(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads"))) {
        self.id = id; self.left = PaneSession(location: left); self.right = PaneSession(location: right)
    }
    public func pane(_ id: PaneID) -> PaneSession { id == .left ? left : right }
    public var activeTab: TabSession { pane(activePane).activeTab }
    @discardableResult public func open(_ location: FileLocation, destination: OpenDestination = .current, inNewTab: Bool = false) -> NavigationTarget {
        let target: PaneID = destination == .current ? activePane : (destination == .left ? .left : .right)
        activePane = target
        let pane = pane(target)
        if inNewTab || (pane.activeTab.pin.isLocked && pane.activeTab.location != location) {
            let tab = TabSession(location: location, options: defaultOptions)
            pane.tabs.append(tab); pane.activeTabID = tab.id
        }
        let tab = pane.activeTab
        return NavigationTarget(paneID: target, tabID: tab.id, ticket: tab.requestNavigation(to: location))
    }
    public func returnToPinnedFolder(in paneID: PaneID, tabID: UUID) -> NavigationTarget? {
        let pane = pane(paneID)
        guard let tab = pane.tabs.first(where: { $0.id == tabID }), let home = tab.pin.home else { return nil }
        pane.activeTabID = tabID; activePane = paneID
        return NavigationTarget(paneID: paneID, tabID: tabID, ticket: tab.requestNavigation(to: home))
    }
}
