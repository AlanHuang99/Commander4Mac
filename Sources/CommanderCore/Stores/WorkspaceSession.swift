// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

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
    public func applyAppearance(_ appearance: ViewAppearance) {
        let valid = appearance.validated()
        defaultOptions.viewAppearance = valid
        for pane in [left, right] {
            for tab in pane.tabs where tab.options.viewAppearance != valid { tab.options.viewAppearance = valid }
        }
    }
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
    public func navigateHistory(in paneID: PaneID, forward: Bool) -> NavigationTarget? {
        let pane = pane(paneID)
        let current = pane.activeTab
        let index = current.historyIndex + (forward ? 1 : -1)
        guard current.history.indices.contains(index) else { return nil }
        activePane = paneID
        if current.pin.isLocked && current.history[index] != current.location {
            let tab = TabSession(location: current.history[index], options: current.options)
            tab.restoreHistory(current.history, index: index)
            pane.tabs.append(tab); pane.activeTabID = tab.id
            return .init(paneID: paneID, tabID: tab.id, ticket: tab.requestNavigation(to: tab.location))
        }
        guard let ticket = forward ? current.goForward() : current.goBack() else { return nil }
        return .init(paneID: paneID, tabID: current.id, ticket: ticket)
    }
}
