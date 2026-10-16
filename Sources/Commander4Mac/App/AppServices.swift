import Foundation
import Observation
import CommanderCore

@MainActor @Observable
final class AppServices {
    static let shared = AppServices()
    let stateStore: ApplicationStateStore
    let preferencesStore: PreferencesStore
    var preferences: Preferences {
        didSet {
            do { try preferencesStore.save(preferences) }
            catch { startupDiagnostic = "Could not save preferences: \(error.localizedDescription)" }
            for controller in controllers.values.compactMap(\.value) { controller.workspace.defaultOptions = preferences.view.validated() }
        }
    }
    let favorites: FavoriteStore
    let shelf: ShelfStore
    let transferQueue: TransferQueue
    let fileActions: LocalFileActions
    let operationGate: OperationGate
    let journal: OperationJournal
    let marker: ActiveOperationMarker
    var jobs: [JobSnapshot] = []
    var recoveryRecords: [JournalRecord] = []
    var conflictPresenter: UUID?
    private var shelfJobs: [UUID: Set<UUID>] = [:]
    private var jobOwners: [UUID: UUID] = [:]
    private var finishedJobs: Set<UUID> = []
    private var observationTask: Task<Void, Never>?
    private var shortActionCount = 0
    var activeJobCount: Int { jobs.filter { !$0.state.isTerminal }.count + shortActionCount }
    func beginFileAction() { shortActionCount += 1; updateMarker() }
    func endFileAction() { shortActionCount = max(0, shortActionCount - 1); updateMarker() }
    private func updateMarker() {
        do {
            try marker.publish(pid: ProcessInfo.processInfo.processIdentifier,
                executablePath: RuntimeIdentity.executableURL?.path ?? "", executableUUID: RuntimeIdentity.executableUUID, activeJobs: activeJobCount)
        } catch { startupDiagnostic = "Could not update operation status: \(error.localizedDescription)" }
    }
    var pendingConflict: TransferConflict? { jobs.compactMap(\.pendingConflict).first }
    var startupDiagnostic: String?
    var isTerminating = false
    var openWorkspaceWindow: (() -> Void)?
    private weak var activeController: WorkspaceController?
    private var incomingFolders: [URL] = []
    func activate(_ controller: WorkspaceController) { activeController = controller }
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
    private var restoredAdditionalWindows = false
    init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.alanhuang.Commander4Mac.dev")
        let settingsStore = PreferencesStore(directory: directory)
        preferencesStore = settingsStore
        let initialPreferences = settingsStore.load()
        preferences = initialPreferences
        stateStore = ApplicationStateStore(directory: directory)
        let loaded = stateStore.loadRecovering()
        favorites = FavoriteStore(items: loaded.state.favorites)
        shelf = ShelfStore(items: loaded.state.shelf)
        let gate = OperationGate(); operationGate = gate
        fileActions = LocalFileActions(gate: gate)
        let operationJournal = OperationJournal(directory: directory.appendingPathComponent("Operations")); journal = operationJournal
        transferQueue = TransferQueue(executor: LocalOperationExecutor(journal: operationJournal), gate: gate)
        marker = ActiveOperationMarker(directory: directory)
         pendingWindows = initialPreferences.restoreSession ? loaded.state.windows : []; startupDiagnostic = loaded.diagnostic
        observationTask = Task { [weak self, transferQueue, operationJournal] in
            let records = try? await BlockingFileWorker.run { try operationJournal.recoverableJobs() }
            self?.recoveryRecords = records ?? []
            for await snapshots in await transferQueue.snapshots() {
                guard let self else { return }
                self.jobs = snapshots
                if let conflict = self.pendingConflict {
                    let owner = self.jobOwners[conflict.jobID]
                    self.conflictPresenter = owner.flatMap { self.controllers[$0]?.value == nil ? nil : $0 } ?? self.controllers.keys.first
                } else { self.conflictPresenter = nil }
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
        activeController = controller
        if !incomingFolders.isEmpty { routeIncoming(to: controller) }
    }
    func unregister(_ controller: WorkspaceController) {
        guard !isTerminating else { return }
        controllers.removeValue(forKey: controller.workspace.id)
        if conflictPresenter == controller.workspace.id { conflictPresenter = controllers.keys.first }
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
            try stateStore.save(.init(windows: windows + pendingWindows, favorites: favorites.items, shelf: shelf.items))
        } catch { startupDiagnostic = "Could not save the workspace: \(error.localizedDescription)" }
    }
}
@MainActor private final class WeakController {
    weak var value: WorkspaceController?
    init(_ value: WorkspaceController) { self.value = value }
}
