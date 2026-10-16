import Observation

/// A lightweight observable command target that does not initialize file services.
/// An uninstalled app can show installation guidance without loading user state.
@MainActor @Observable final class WindowCommandContext {
    static let shared = WindowCommandContext()
    weak var controller: WorkspaceController?
}
