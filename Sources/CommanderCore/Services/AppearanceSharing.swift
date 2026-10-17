// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

@MainActor public enum AppearanceSharing {
    public static func update(_ appearance: ViewAppearance, selectedTab: TabSession?, preferences: Preferences,
                              workspaces: [WorkspaceSession]) -> Preferences {
        var result = preferences
        let valid = appearance.validated()
        if preferences.shareAppearanceChanges || selectedTab == nil {
            result.view.viewAppearance = valid
            for workspace in workspaces { workspace.defaultOptions.viewAppearance = valid }
        }
        if preferences.shareAppearanceChanges {
            for workspace in workspaces { workspace.applyAppearance(valid) }
        } else if let selectedTab { selectedTab.options.viewAppearance = valid }
        return result
    }
}
