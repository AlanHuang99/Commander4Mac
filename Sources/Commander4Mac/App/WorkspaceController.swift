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
    var showConnections = false
    var editingConnection: ConnectionProfile?
    var editingConnectionRequest: ConnectionOpenRequest?
    var renameRequest: UUID?
    var renamePane: PaneID?
    let quickLook = QuickLookController()
    @ObservationIgnored var forceWindowClose = false
    @ObservationIgnored weak var window: NSWindow?
    enum FieldFocus { case path, filter, files }
    struct FocusRequest { let id = UUID(); let pane: PaneID; let field: FieldFocus }
    var focusRequest: FocusRequest?
    var isEditingText: Bool { window?.firstResponder is NSTextView }
    func focus(_ field: FieldFocus) { focusRequest = .init(pane: workspace.activePane, field: field) }
    func newTab() { open(workspace.activeTab.location, newTab: true) }
    func closeTab() {
        let pane = workspace.pane(workspace.activePane)
        if pane.tabs.count == 1 && !pane.activeTab.pin.isPinned { closeWindow() }
        else { pane.close(tabID: pane.activeTabID); services.saveSoon() }
    }
    func closeWindow() {
        forceWindowClose = true; defer { forceWindowClose = false }
        window?.performClose(nil)
    }
    func openSelection() { for entry in workspace.activeTab.selectedEntries { activate(entry, pane: workspace.activePane) } }
    func previewSelection() {
        guard workspace.activeTab.location.isLocal else { errorMessage = "Download this file to a local pane to preview it."; return }
        quickLook.present(CommandRouter.previewItems(in: workspace))
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.directoryURL = workspace.activeTab.location.isLocal ? workspace.activeTab.location.url : FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK, let url = panel.url { open(.local(url)) }
    }
    @ObservationIgnored weak var undoManager: UndoManager?
    init(services: AppServices = .shared) {
        self.services = services
        let initial = WorkspaceSession()
        workspace = initial
        loader = DirectoryLoader(workspace: initial, provider: ProviderRouter(remote: services.remote))
    }
    func start() async -> Int {
        guard !started else { return 0 }; started = true
        let restored = services.nextRestoredWorkspace()
        if let restored { workspace = restored; loader = DirectoryLoader(workspace: restored, provider: ProviderRouter(remote: services.remote)) }
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
            let generation = tab.generation
            let resolution = try? await BlockingFileWorker.run { LocationResolver().resolve(reference) }
            guard tab.generation == generation, workspace.pane(paneID).tabs.contains(where: { $0 === tab }) else { return }
            switch resolution {
            case .available(let location):
                tab.unresolvedReference = nil; _ = tab.requestNavigation(to: location)
                tab.savedReference = .init(bookmark: reference.bookmark, displayURL: location.url, expectedIdentity: reference.expectedIdentity)
            case .unavailable, .needsRelink, .none:
                let ticket = tab.requestNavigation(to: .local(reference.displayURL))
                tab.unresolvedReference = reference
                _ = tab.fail(CocoaError(.fileReadNoSuchFile), for: ticket)
                return
            }
        }
        let ticket = tab.requestNavigation(to: tab.location)
        await loader.load(target: .init(paneID: paneID, tabID: tab.id, ticket: ticket), options: .init(includeHidden: tab.options.includeHidden))
    }
    func manageConnection(_ profile: ConnectionProfile? = nil, request: ConnectionOpenRequest? = nil) { editingConnection = profile; editingConnectionRequest = request; showConnections = true }
    func connectSaved(_ profile: ConnectionProfile, destination: OpenDestination? = nil) {
        do {
            let request = try ConnectionOpenRequest(profile: profile, activePane: workspace.activePane, destination: destination, defaultDestination: services.preferences.defaultDestination)
            Task {
                do {
                    if await services.remote.isConnected(profile.id) { try await establishConnection(request, secret: ""); return }
                    let stored = try await services.connections.secret(for: profile)
                    guard let credential = stored ?? (profile.authentication != .password ? "" : nil) else { manageConnection(profile, request: request); return }
                    try await establishConnection(request, secret: credential)
                } catch is CancellationError { }
                catch { errorMessage = error.localizedDescription }
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func establishConnection(_ request: ConnectionOpenRequest, secret: String, onProfileChange: ((ConnectionProfile) -> Void)? = nil) async throws {
        let attempt = UUID(); let remote = services.remote
        try await withTaskCancellationHandler {
            try await performConnection(request, secret: secret, attempt: attempt, onProfileChange: onProfileChange)
        } onCancel: { Task { await remote.cancelAttempt(attempt) } }
    }
    private func performConnection(_ request: ConnectionOpenRequest, secret: String, attempt: UUID, onProfileChange: ((ConnectionProfile) -> Void)?) async throws {
        try Task.checkCancellation()
        var profile = request.profile
        do { try await services.remote.connect(profile, secret: secret, attempt: attempt) }
        catch let challenge as HostKeyChallenge {
            try Task.checkCancellation()
            let alert = NSAlert(); alert.alertStyle = challenge.previousFingerprint == nil ? .informational : .warning
            alert.messageText = challenge.previousFingerprint == nil ? "Verify SFTP Server" : "SSH Host Key Changed"
            var message = "Server: \(challenge.host):\(challenge.port)\nKey type: \(challenge.observedKey.split(separator: " ").first.map(String.init) ?? "SSH")\nFingerprint: \(challenge.fingerprint)"
            if let previous = challenge.previousFingerprint { message += "\nPreviously trusted: " + previous }
            message += "\n\nVerify this fingerprint through a trusted channel before trusting it."
            alert.informativeText = message
            alert.addButton(withTitle: challenge.previousFingerprint == nil ? "Trust and Connect" : "Trust Changed Key")
            alert.addButton(withTitle: "Cancel"); alert.buttons[0].keyEquivalent = ""; alert.buttons[1].keyEquivalent = "\r"
            guard alert.runModal() == .alertFirstButtonReturn else { await services.remote.cancelAttempt(attempt); throw CancellationError() }
            try Task.checkCancellation()
            profile = try await services.connections.trust(challenge.observedKey, for: profile)
            try Task.checkCancellation()
            onProfileChange?(profile)
            try await services.remote.connect(profile, secret: secret, attempt: attempt)
        }
        try Task.checkCancellation()
        guard window?.isVisible == true else { return }
        let verifiedLocation = FileLocation.remote(kind: profile.protocolKind, profileID: profile.id, path: request.location.remotePath!)
        open(verifiedLocation, in: request.paneID)
    }
    func openPath(_ text: String, in pane: PaneID) {
        do { open(try PathNavigation.resolve(text, from: workspace.pane(pane).activeTab.location), in: pane) }
        catch { errorMessage = error.localizedDescription }
    }
    func open(_ location: FileLocation, in paneID: PaneID? = nil, newTab: Bool = false) {
        let destination: OpenDestination = paneID.map { $0 == .left ? .left : .right } ?? .current
        let target = workspace.open(location, destination: destination, inNewTab: newTab)
        focus(.files)
        let tab = workspace.pane(target.paneID).activeTab
        Task { await loader.load(target: target, options: .init(includeHidden: tab.options.includeHidden)); services.saveSoon() }
    }
    func addFavorite() {
        guard workspace.activeTab.location.isLocal else { errorMessage = "Save remote folders through Connections."; return }
        let location = workspace.activeTab.location
        Task {
            do { try await services.favorites.add(name: location.title, location: location); services.saveSoon() }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func openFavorite(_ favorite: Favorite, destination: OpenDestination? = nil, newTab: Bool = false) {
        let route = destination ?? favorite.destination ?? services.preferences.defaultDestination
        let pane: PaneID = route == .current ? workspace.activePane : (route == .left ? .left : .right)
        Task {
            do {
                let resolution = try await BlockingFileWorker.run { LocationResolver().resolve(favorite.reference) }
                switch resolution {
                case .available(let location): open(location, in: pane, newTab: newTab)
                case .unavailable(let message), .needsRelink(let message): errorMessage = message
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func relinkFavorite(_ favorite: Favorite) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.message = "Choose the folder for this favorite."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let reference = try await BlockingFileWorker.run { try LocationResolver().reference(for: .local(url)) }
                if let index = services.favorites.items.firstIndex(where: { $0.id == favorite.id }) {
                    services.favorites.items[index].reference = reference; services.saveSoon()
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func relinkStagedItem(_ item: StagedItem) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.allowsMultipleSelection = false; panel.message = "Choose the item to use for this shelf reference."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { try await services.shelf.relink(id: item.id, to: .local(url)); services.saveSoon() }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func renameFavorite(_ favorite: Favorite) {
        let alert = NSAlert(); alert.messageText = "Rename Favorite"
        let field = NSTextField(string: favorite.name); field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "Rename"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { services.favorites.rename(id: favorite.id, to: field.stringValue); services.saveSoon() }
    }
    func activate(_ entry: FileEntry, pane: PaneID) {
        if !entry.location.isLocal {
            if entry.kind == .directory { open(entry.location, in: pane) }
            else { errorMessage = entry.kind == .symbolicLink ? "Remote symlinks are not opened. Browse the target path directly." : "Copy this remote file to a local pane to open or preview it." }
            return
        }
        workspace.activePane = pane
        if CommandRouter.openDisposition(kind: entry.kind) == .browse { open(entry.location, in: pane) }
        else if entry.kind == .symbolicLink {
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: entry.location.url.path, isDirectory: &directory), directory.boolValue { open(entry.location, in: pane) }
            else { if !SystemFileActions.open([entry.location]) { errorMessage = "No application could open this item." } }
        } else { if !SystemFileActions.open([entry.location]) { errorMessage = "No application could open this item." } }
    }
    func selectTab(_ tab: TabSession, pane: PaneID) {
        let paneState = workspace.pane(pane)
        if paneState.activeTabID != tab.id { tab.switchStartedAt = ProcessInfo.processInfo.systemUptime }
        workspace.activePane = pane; focus(.files)
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
        guard let target = workspace.navigateHistory(in: paneID, forward: forward) else { return }
        let tab = workspace.pane(paneID).activeTab
        focus(.files)
        Task { await loader.load(target: target, options: .init(includeHidden: tab.options.includeHidden)); services.saveSoon() }
    }
    func rename(_ entry: FileEntry, to name: String, pane: PaneID) {
        guard name != entry.name else { return }
        Task {
            do {
                services.beginFileAction(); defer { services.endFileAction() }
                if !entry.location.isLocal {
                    let target = try entry.location.parent.appending(try FileNameRules.validateComponent(name))
                    await services.operationGate.acquire()
                    do {
                        guard try await services.remote.metadata(target) == nil else { throw FileOperationError.message("An item already has that name on the server.") }
                        try await services.remote.rename(entry.location, to: target)
                        await services.operationGate.release()
                    } catch { await services.operationGate.release(); throw error }
                    undoManager?.removeAllActions(withTarget: self)
                    await refresh(pane)
                    if workspace.pane(pane).activeTab.location == target.parent { workspace.pane(pane).activeTab.selection = [EntryID(target.url)] }
                    return
                }
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
                if !parent.isLocal {
                    let target = try parent.appending(try FileNameRules.validateComponent(name))
                    await services.operationGate.acquire()
                    do { try await services.remote.createDirectory(target); await services.operationGate.release() }
                    catch { await services.operationGate.release(); throw error }
                    undoManager?.removeAllActions(withTarget: self)
                    await refresh(pane)
                    if workspace.pane(pane).activeTab.location == parent { workspace.pane(pane).activeTab.selection = [EntryID(target.url)] }
                    return
                }
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
        guard workspace.activeTab.location.isLocal else { errorMessage = "Remote Trash is not available. No files were deleted."; return }
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
        guard workspace.activeTab.location.isLocal else { errorMessage = "The shelf currently holds local file references. Use Copy to Other Pane for remote files."; return }
        let locations = workspace.activeTab.selectedEntries.map(\.location)
        guard !locations.isEmpty else { return }
        Task {
            do { try await services.shelf.stage(locations); services.saveSoon(); shelfVisible = true }
            catch { errorMessage = error.localizedDescription }
        }
    }
    func transferSelection(_ kind: TransferKind, from pane: PaneID) {
        workspace.activePane = pane
        guard let request = CommandRouter.transfer(kind, in: workspace, textEditing: isEditingText) else { return }
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
        case .preview: previewSelection()
        case .showPackage:
            if let entry = workspace.activeTab.selectedEntries.first, entry.kind == .package { open(CommandRouter.packageContents(entry.location), in: pane) }
        case .rename: if workspace.activeTab.selection.count == 1 { renamePane = pane; renameRequest = UUID() }
        case .newFolder: newFolder()
        case .trash: trashSelection()
        case .copyClipboard:
            guard workspace.activeTab.location.isLocal else { errorMessage = "Use Copy to Other Pane to download remote files."; return }
            FilePasteboard.write(workspace.activeTab.selectedEntries.map(\.location))
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
