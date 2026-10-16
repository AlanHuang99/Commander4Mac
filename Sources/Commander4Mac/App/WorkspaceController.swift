import Foundation
import Observation
import AppKit
import CommanderCore

@MainActor @Observable
final class WorkspaceController {
    var workspace: WorkspaceSession
    var loader: DirectoryLoader
    let services: AppServices
    private var started = false
    var errorMessage: String?
    var sidebarVisible = true
    var shelfVisible = true
    var activityVisible = false
    var renameRequest: UUID?
    var renamePane: PaneID?
    @ObservationIgnored weak var undoManager: UndoManager?
    init(services: AppServices = .shared) {
        self.services = services
        let initial = WorkspaceSession()
        workspace = initial
        loader = DirectoryLoader(workspace: initial)
    }
    func start() async -> Int {
        guard !started else { return 0 }; started = true
        let restored = services.nextRestoredWorkspace()
        if let restored { workspace = restored; loader = DirectoryLoader(workspace: restored) }
        workspace.defaultOptions = services.preferences.view.validated()
        if restored == nil {
            workspace.left.activeTab.options = services.preferences.view
            workspace.right.activeTab.options = services.preferences.view
        }
        services.register(self)
        errorMessage = services.startupDiagnostic
        await refresh(.left); await refresh(.right)
        return services.additionalWindowsToRestore()
    }
    func refresh(_ paneID: PaneID) async {
        let tab = workspace.pane(paneID).activeTab
        if let reference = tab.unresolvedReference {
            switch LocationResolver().resolve(reference) {
            case .available(let location): tab.unresolvedReference = nil; _ = tab.requestNavigation(to: location)
            case .unavailable, .needsRelink:
                let ticket = tab.requestNavigation(to: .local(reference.displayURL))
                tab.unresolvedReference = reference
                _ = tab.fail(CocoaError(.fileReadNoSuchFile), for: ticket)
                return
            }
        }
        let ticket = tab.requestNavigation(to: tab.location)
        await loader.load(target: .init(paneID: paneID, tabID: tab.id, ticket: ticket), options: .init(includeHidden: tab.options.includeHidden))
    }
    func open(_ location: FileLocation, in paneID: PaneID? = nil, newTab: Bool = false) {
        let destination: OpenDestination = paneID.map { $0 == .left ? .left : .right } ?? .current
        let target = workspace.open(location, destination: destination, inNewTab: newTab)
        let tab = workspace.pane(target.paneID).activeTab
        Task { await loader.load(target: target, options: .init(includeHidden: tab.options.includeHidden)); services.saveSoon() }
    }
    func addFavorite() {
        do { try services.favorites.add(name: workspace.activeTab.location.title, location: workspace.activeTab.location); services.saveSoon() }
        catch { errorMessage = error.localizedDescription }
    }
    func openFavorite(_ favorite: Favorite, destination: OpenDestination? = nil, newTab: Bool = false) {
        switch LocationResolver().resolve(favorite.reference) {
        case .available(let location):
            let route = destination ?? favorite.destination ?? services.preferences.defaultDestination
            let pane: PaneID? = route == .current ? nil : (route == .left ? .left : .right)
            open(location, in: pane, newTab: newTab)
        case .unavailable(let message), .needsRelink(let message): errorMessage = message
        }
    }
    func renameFavorite(_ favorite: Favorite) {
        let alert = NSAlert(); alert.messageText = "Rename Favorite"
        let field = NSTextField(string: favorite.name); field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { services.favorites.rename(id: favorite.id, to: field.stringValue); services.saveSoon() }
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
    func rename(_ entry: FileEntry, to name: String, pane: PaneID) {
        guard name != entry.name else { return }
        Task {
            do {
                services.beginFileAction(); defer { services.endFileAction() }
                let mutation = try await services.fileActions.rename(entry.location, to: name)
                registerUndo(mutation, name: "Rename")
                await refresh(pane)
                if workspace.pane(pane).activeTab.location == mutation.after.parent { workspace.pane(pane).activeTab.selection = [EntryID(mutation.after.url)] }
            } catch { errorMessage = error.localizedDescription; await refresh(pane) }
        }
    }
    func newFolder() {
        let pane = workspace.activePane
        let parent = workspace.activeTab.location
        let alert = NSAlert(); alert.messageText = "New Folder"
        alert.informativeText = parent.url.path
        let field = NSTextField(string: "New Folder"); field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "Create"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue
        Task {
            do {
                services.beginFileAction(); defer { services.endFileAction() }
                let mutation = try await services.fileActions.createDirectory(named: name, in: parent)
                registerUndo(mutation, name: "New Folder")
                await refresh(pane)
                if workspace.pane(pane).activeTab.location == parent { workspace.pane(pane).activeTab.selection = [EntryID(mutation.after.url)] }
            } catch { errorMessage = error.localizedDescription }
        }
    }
    private func registerUndo(_ mutation: LocalMutation, name: String) {
        undoManager?.registerUndo(withTarget: self) { target in
            Task { @MainActor in
                do {
                    target.services.beginFileAction(); defer { target.services.endFileAction() }
                    try await target.services.fileActions.undo(mutation)
                    await target.refresh(.left); await target.refresh(.right)
                } catch { target.errorMessage = error.localizedDescription }
            }
        }
        undoManager?.setActionName(name)
    }
    func trashSelection() {
        let locations = workspace.activeTab.selectedEntries.map(\.location)
        guard !locations.isEmpty else { return }
        Task {
            services.beginFileAction(); defer { services.endFileAction() }
            let results = await services.fileActions.trash(locations)
            let failures = results.filter { $0.state != .completed }
            if !failures.isEmpty { errorMessage = failures.map { $0.source.url.lastPathComponent + ": " + ($0.detail ?? "Could not move to Trash") }.joined(separator: "\n") }
            await refresh(.left); await refresh(.right)
        }
    }
    func paste(_ kind: TransferKind) {
        let sources = FilePasteboard.readLocations()
        guard !sources.isEmpty else { return }
        services.enqueue(.init(kind: kind, sources: sources, destinationDirectory: workspace.activeTab.location), owner: workspace.id)
        activityVisible = true
    }
    func acceptDrop(_ request: TransferRequest) { services.enqueue(request, owner: workspace.id); activityVisible = true }
    func stageSelection() {
        let locations = workspace.activeTab.selectedEntries.map(\.location)
        guard !locations.isEmpty else { return }
        Task {
            do { try await services.shelf.stage(locations); services.saveSoon(); shelfVisible = true }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func transferSelection(_ kind: TransferKind, from pane: PaneID) {
        let sources = workspace.pane(pane).activeTab.selectedEntries.map(\.location)
        guard !sources.isEmpty else { return }
        let request = TransferRequest(kind: kind, sources: sources, destinationDirectory: workspace.pane(pane.opposite).activeTab.location)
        services.enqueue(request, owner: workspace.id); activityVisible = true
    }
    func transferShelf(_ kind: TransferKind, to pane: PaneID) {
        let destination = workspace.pane(pane).activeTab.location
        let ids = Set(services.shelf.items.map(\.id))
        Task {
            do {
                let sources = try await services.shelf.resolvedLocations(ids: ids)
                guard !sources.isEmpty else { return }
                services.enqueue(.init(kind: kind, sources: sources, destinationDirectory: destination), owner: workspace.id, shelfIDs: ids)
                services.saveSoon(); activityVisible = true
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func tableCommand(_ command: TableCommand, pane: PaneID) {
        workspace.activePane = pane
        switch command {
        case .rename: if workspace.activeTab.selection.count == 1 { renamePane = pane; renameRequest = UUID() }
        case .newFolder: newFolder()
        case .trash: trashSelection()
        case .copyClipboard: FilePasteboard.write(workspace.activeTab.selectedEntries.map(\.location))
        case .pasteClipboard: paste(.copy)
        case .moveClipboard: paste(.move)
        case .copyPath:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(workspace.activeTab.selectedEntries.map { $0.location.url.path }.joined(separator: "\n"), forType: .string)
        case .stage: stageSelection()
        case .copy: transferSelection(.copy, from: pane)
        case .move: transferSelection(.move, from: pane)
        case .focusOther: workspace.activePane = pane.opposite
        case .parent: open(workspace.pane(pane).activeTab.location.parent, in: pane)
        case .open: if let entry = workspace.activeTab.selectedEntries.first { activate(entry, pane: pane) }
        default: break
        }
    }
}
