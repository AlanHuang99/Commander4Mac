import Foundation
import OSLog
import CommanderCore

@MainActor enum RuntimeMetrics {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Commander4Mac", category: "Performance")
    static func record(_ name: String, since start: TimeInterval) {
        guard start > 0 else { return }
        let milliseconds = max(0, (ProcessInfo.processInfo.systemUptime - start) * 1_000)
        logger.info("metric=\(name, privacy: .public) ms=\(milliseconds, privacy: .public)")
    }
    static func rendered(_ tab: TabSession, lastGeneration: inout UInt64?) {
        if tab.snapshot != nil, !tab.isLoading, lastGeneration != tab.generation {
            lastGeneration = tab.generation; record("rowsVisible", since: tab.loadStartedAt)
        }
        if let start = tab.switchStartedAt, tab.snapshot != nil {
            record("cachedTabVisible", since: start); tab.switchStartedAt = nil
        }
    }
}
