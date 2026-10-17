// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
import AppKit
import Observation
import OSLog
import CommanderCore

@MainActor @Observable
final class AppServices {
    static let shared = AppServices()
    let stateStore: ApplicationStateStore
    private let persistence: SessionPersistence
    let preferencesStore: PreferencesStore
    var preferences: Preferences {
        didSet {
            do { try preferencesStore.save(preferences) }
            catch { startupDiagnostic = "Could not save preferences: \(error.localizedDescription)" }
            for controller in controllers.values.compactMap(\.value) { controller.workspace.defaultOptions = preferences.view.validated() }
        }
    }
    let remote = RemoteConnectionManager()
    let connections: ConnectionController
    let favorites: FavoriteStore
    let shelf: ShelfStore
    let transferQueue: TransferQueue
    let fileActions: LocalFileActions
    let operationGate: OperationGate
    let journal: OperationJournal
    let marker: ActiveOperationMarker
    var jobs: [JobSnapshot] = []
    var recoveryDiagnostic: String?
    var recoveryRecords: [JournalRecord] = []
    private let conflictRouting = ConflictPresentationRouter()
    var conflictPresenter: UUID? { conflictRouting.presenter }
    private var shelfJobs: [UUID: Set<UUID>] = [:]
    private var jobOwners: [UUID: UUID] = [:]
    private static let operationsLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Commander4Mac", category: "Operations")
    private var jobStates: [UUID: JobState] = [:]
    private var finishedJobs: Set<UUID> = []
    private var observationTask: Task<Void, Never>?
    private var shortActionCount = 0
    private var lastPublishedActivityCount: Int?
    var activeJobCount: Int { jobs.filter { !$0.state.isTerminal }.count + shortActionCount }
    func beginFileAction() { shortActionCount += 1; updateMarker() }
    func endFileAction() { shortActionCount = max(0, shortActionCount - 1); updateMarker() }
    private func updateMarker() {
        guard lastPublishedActivityCount != activeJobCount else { return }
        do {
            try marker.publish(pid: ProcessInfo.processInfo.processIdentifier,
                executablePath: RuntimeIdentity.executableURL?.path ?? "", executableUUID: RuntimeIdentity.executableUUID, activeJobs: activeJobCount)
            lastPublishedActivityCount = activeJobCount
        } catch { startupDiagnostic = "Could not update operation status: \(error.localizedDescription)" }
    }
    var pendingConflict: TransferConflict? { jobs.compactMap(\.pendingConflict).first }
    var startupDiagnostic: String?
    var isTerminating = false
    var openWorkspaceWindow: (() -> Void)?
    private weak var activeController: WorkspaceController?
    private var incomingFolders: [URL] = []
    @ObservationIgnored private var commandUpdateObserver: NotificationToken?
    func activate(_ controller: WorkspaceController) { activeController = controller; invalidateCommandFocus() }
    func invalidateCommandFocus() {
        let target = commandController(for: NSApp.keyWindow)
        if WindowCommandContext.shared.controller !== target { WindowCommandContext.shared.controller = target }
    }
    func commandController(for window: NSWindow?) -> WorkspaceController? {
        guard NSApp.isActive, let window, window.isKeyWindow, window.attachedSheet == nil, NSApp.modalWindow == nil else { return nil }
        return controllers.values.compactMap(\.value).first { $0.window === window }
    }
    func acceptIncomingFolders(_ urls: [URL]) {
        incomingFolders.append(contentsOf: urls)
        if let controller = activeController ?? controllers.values.compactMap(\.value).first { routeIncoming(to: controller) }
        else { openWorkspaceWindow?() }
    }
    private func routeIncoming(to controller: WorkspaceController) {
        let folders = incomingFolders; incomingFolders = []
        let route = preferences.defaultDestination
        let pane: PaneID? = route == .current ? nil : (route == .left ? .left : .right)
        for url in folders { controller.open(.local(url), in: pane, newTab: true) }
    }
    private var pendingWindows: [WorkspaceSnapshot]
    private var controllers: [UUID: WeakController] = [:]
    private var saveTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var saveRevision: UInt64 = 0
    private var restoredAdditionalWindows = false
    init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.alanhuang.Commander4Mac.dev")
        let settingsStore = PreferencesStore(directory: directory)
        preferencesStore = settingsStore
        let initialPreferences = settingsStore.load()
        preferences = initialPreferences
        stateStore = ApplicationStateStore(directory: directory)
        persistence = SessionPersistence(store: stateStore)
        connections = ConnectionController(remote: remote, directory: directory)
        let loaded = stateStore.loadRecovering()
        favorites = FavoriteStore(items: loaded.state.favorites)
        shelf = ShelfStore(items: loaded.state.shelf)
        let gate = OperationGate(); operationGate = gate
        fileActions = LocalFileActions(gate: gate)
        let operationJournal = OperationJournal(directory: directory.appendingPathComponent("Operations")); journal = operationJournal
        transferQueue = TransferQueue(executor: RemoteTransferExecutor(remote: remote, journal: operationJournal), gate: gate)
        marker = ActiveOperationMarker(directory: directory)
         pendingWindows = initialPreferences.restoreSession ? loaded.state.windows : []; startupDiagnostic = loaded.diagnostic
        // AppKit can end a sheet after its key-window notification. Publish only
        // actual target changes at the end of the native update cycle.
        commandUpdateObserver = NotificationToken(NotificationCenter.default.addObserver(forName: NSApplication.didUpdateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidateCommandFocus() }
        })
        observationTask = Task { [weak self, transferQueue, operationJournal] in
            do { self?.recoveryRecords = try await BlockingFileWorker.run { try operationJournal.recoverableJobs() } }
            catch { self?.recoveryDiagnostic = "Could not read interrupted-operation records: \(error.localizedDescription)" }
            for await snapshots in await transferQueue.snapshots() {
                guard let self else { return }
                self.jobs = snapshots
                for job in snapshots where self.jobStates[job.id] != job.state {
                    self.jobStates[job.id] = job.state
                    Self.operationsLog.info("job=\(job.id.uuidString, privacy: .public) state=\(job.state.rawValue, privacy: .public)")
                }
                if let conflict = self.pendingConflict {
                    self.conflictRouting.setPending(owner: self.jobOwners[conflict.jobID])
                } else { self.conflictRouting.clearPending() }
                for job in snapshots where job.state.isTerminal && !self.finishedJobs.contains(job.id) {
                    self.finishedJobs.insert(job.id)
                    if let ids = self.shelfJobs.removeValue(forKey: job.id) {
                        self.shelf.apply(.init(jobID: job.id, outcomes: job.outcomes, state: job.state), capturedIDs: ids)
                        self.saveSoon()
                    }
                    for controller in self.controllers.values.compactMap(\.value) {
                        Task { await controller.refresh(.left); await controller.refresh(.right) }
                    }
                }
                self.updateMarker()
            }
        }
    }
    func keepRecoveryFiles(_ record: JournalRecord) {
        Task {
            var reviewed = record; reviewed.phase = .complete; reviewed.detail = "Reviewed by the user. Files retained without replay."
            do {
                let journal = journal; let captured = reviewed
                try await BlockingFileWorker.run { try journal.record(captured) }
                recoveryRecords.removeAll { $0.itemID == record.itemID }
            } catch { recoveryDiagnostic = error.localizedDescription }
        }
    }
    func enqueue(_ request: TransferRequest, owner: UUID, shelfIDs: Set<UUID>? = nil) {
        jobOwners[request.id] = owner
        if let shelfIDs { shelfJobs[request.id] = shelfIDs }
        Task { await transferQueue.enqueue(request) }
    }
    func resolve(_ conflict: TransferConflict, _ resolution: ConflictResolution) {
        Task { await transferQueue.resolveConflict(jobID: conflict.jobID, conflictID: conflict.id, resolution: resolution) }
    }
    func nextRestoredWorkspace() -> WorkspaceSession? { pendingWindows.isEmpty ? nil : pendingWindows.removeFirst().restore() }
    func additionalWindowsToRestore() -> Int {
        guard !restoredAdditionalWindows else { return 0 }
        restoredAdditionalWindows = true; return pendingWindows.count
    }
    func register(_ controller: WorkspaceController) {
        controllers[controller.workspace.id] = WeakController(controller)
        conflictRouting.register(controller.workspace.id)
        activeController = controller
        if !incomingFolders.isEmpty { routeIncoming(to: controller) }
    }
    func unregister(_ controller: WorkspaceController) {
        guard !isTerminating else { return }
        controllers.removeValue(forKey: controller.workspace.id); invalidateCommandFocus()
        conflictRouting.unregister(controller.workspace.id)
        saveNow()
    }
    func saveSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            self?.saveNow()
        }
    }
    func saveNow() {
        saveTask?.cancel()
        do {
            let windows = try controllers.values.compactMap(\.value).map { try WorkspaceSnapshot($0.workspace) }
            let captured = SavedApplicationState(windows: windows + pendingWindows, favorites: favorites.items, shelf: shelf.items)
            saveRevision &+= 1
            let revision = saveRevision; let persistence = persistence
            let previous = persistenceTask
            persistenceTask = Task { [weak self] in
                // Preserve capture order even if tasks are scheduled out of order.
                await previous?.value
                do {
                    if let saved = try await persistence.save(captured, revision: revision), let self {
                        for window in saved.windows {
                            for controller in self.controllers.values.compactMap(\.value) { window.applyReferences(to: controller.workspace) }
                        }
                    }
                } catch { self?.startupDiagnostic = "Could not save the workspace: \(error.localizedDescription)" }
            }
        } catch { startupDiagnostic = "Could not save the workspace: \(error.localizedDescription)" }
    }
    func flushState() async { saveNow(); await persistenceTask?.value }
}
@MainActor private final class WeakController {
    weak var value: WorkspaceController?
    init(_ value: WorkspaceController) { self.value = value }
}
