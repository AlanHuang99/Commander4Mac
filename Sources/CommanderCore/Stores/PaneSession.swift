// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
import Observation

@MainActor @Observable
public final class PaneSession {
    public var tabs: [TabSession]
    public var activeTabID: UUID
    public var activeTab: TabSession { tabs.first { $0.id == activeTabID } ?? tabs[0] }
    public init(location: FileLocation, options: ViewOptions = .init()) {
        let tab = TabSession(location: location, options: options); tabs = [tab]; activeTabID = tab.id
    }
    @discardableResult public func close(tabID: UUID) -> Bool {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == tabID }), !tabs[index].pin.isPinned else { return false }
        tabs.remove(at: index)
        if activeTabID == tabID { activeTabID = tabs[min(index, tabs.count - 1)].id }
        return true
    }
}
