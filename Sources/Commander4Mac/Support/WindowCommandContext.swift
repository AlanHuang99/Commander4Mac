// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Observation

/// A lightweight observable command target that does not initialize file services.
/// An uninstalled app can show installation guidance without loading user state.
@MainActor @Observable final class WindowCommandContext {
    static let shared = WindowCommandContext()
    weak var controller: WorkspaceController?
}
