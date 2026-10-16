import Foundation
import Observation
import AppKit
import CommanderCore

@MainActor @Observable
final class WorkspaceController {
    let workspace: WorkspaceSession
    let loader: DirectoryLoader
    var errorMessage: String?
    var sidebarVisible = true
    init() {
        workspace = WorkspaceSession()
        loader = DirectoryLoader(workspace: workspace)
    }
    func start() async {
        await refresh(.left); await refresh(.right)
    }
    func refresh(_ paneID: PaneID) async {
        let tab = workspace.pane(paneID).activeTab
        let ticket = tab.requestNavigation(to: tab.location)
        await loader.load(target: .init(paneID: paneID, tabID: tab.id, ticket: ticket), options: .init(includeHidden: tab.options.includeHidden))
    }
    func open(_ location: FileLocation, in paneID: PaneID? = nil, newTab: Bool = false) {
        let destination: OpenDestination = paneID.map { $0 == .left ? .left : .right } ?? .current
        let target = workspace.open(location, destination: destination, inNewTab: newTab)
        let tab = workspace.pane(target.paneID).activeTab
        Task { await loader.load(target: target, options: .init(includeHidden: tab.options.includeHidden)) }
    }
    func activate(_ entry: FileEntry, pane: PaneID) {
        workspace.activePane = pane
        if entry.isDirectory { open(entry.location, in: pane) }
        else if entry.kind == .symbolicLink {
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: entry.location.url.path, isDirectory: &directory), directory.boolValue { open(entry.location, in: pane) }
            else { NSWorkspace.shared.open(entry.location.url) }
        } else { NSWorkspace.shared.open(entry.location.url) }
    }
    func selectTab(_ tab: TabSession, pane: PaneID) {
        let paneState = workspace.pane(pane)
        if paneState.activeTabID == tab.id, tab.pin.home != nil {
            if let target = workspace.returnToPinnedFolder(in: pane, tabID: tab.id) {
                Task { await loader.load(target: target, options: .init(includeHidden: tab.options.includeHidden)) }
            }
        } else {
            paneState.activeTabID = tab.id; workspace.activePane = pane
            Task { await refresh(pane) }
        }
    }
    func history(_ paneID: PaneID, forward: Bool) {
        let tab = workspace.pane(paneID).activeTab
        guard let ticket = forward ? tab.goForward() : tab.goBack() else { return }
        Task { await loader.load(target: .init(paneID: paneID, tabID: tab.id, ticket: ticket), options: .init(includeHidden: tab.options.includeHidden)) }
    }
    func tableCommand(_ command: TableCommand, pane: PaneID) {
        workspace.activePane = pane
        switch command {
        case .focusOther: workspace.activePane = pane.opposite
        case .parent: open(workspace.pane(pane).activeTab.location.parent, in: pane)
        case .open: if let entry = workspace.activeTab.selectedEntries.first { activate(entry, pane: pane) }
        default: break
        }
    }
}
