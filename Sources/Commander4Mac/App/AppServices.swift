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
    var stagedItems: [StagedItem]
    var startupDiagnostic: String?
    var isTerminating = false
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
        stagedItems = loaded.state.shelf; pendingWindows = initialPreferences.restoreSession ? loaded.state.windows : []; startupDiagnostic = loaded.diagnostic
    }
    func nextRestoredWorkspace() -> WorkspaceSession? { pendingWindows.isEmpty ? nil : pendingWindows.removeFirst().restore() }
    func additionalWindowsToRestore() -> Int {
        guard !restoredAdditionalWindows else { return 0 }
        restoredAdditionalWindows = true; return pendingWindows.count
    }
    func register(_ controller: WorkspaceController) { controllers[controller.workspace.id] = WeakController(controller) }
    func unregister(_ controller: WorkspaceController) {
        guard !isTerminating else { return }
        controllers.removeValue(forKey: controller.workspace.id); saveNow()
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
            try stateStore.save(.init(windows: windows + pendingWindows, favorites: favorites.items, shelf: stagedItems))
        } catch { startupDiagnostic = "Could not save the workspace: \(error.localizedDescription)" }
    }
}
@MainActor private final class WeakController {
    weak var value: WorkspaceController?
    init(_ value: WorkspaceController) { self.value = value }
}
