// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
import CommanderCore

@MainActor final class LocalPerformanceTests: XCTestCase {
    func testTenThousandEntryWarmListingCachedSwitchAndMainActorDuringCopy() async throws {
        guard ProcessInfo.processInfo.environment["COMMANDER_PERFORMANCE"] == "1" else { throw XCTSkip("Opt-in 10,000-entry performance fixture") }
        let f = try FixtureDirectory(); let source = try f.directory("ten-thousand"); let destination = try f.directory("destination")
        try await BlockingFileWorker.run {
            for index in 0..<10_000 { try Data("fixture".utf8).write(to: source.appendingPathComponent(String(format: "entry-%05d.txt", index))) }
        }
        let provider = LocalFileSystem(); let location = FileLocation.local(source)
        let warm = try await provider.list(location, options: .init())
        XCTAssertEqual(warm.entries.count, 10_000)
        var listing: [Double] = []
        var rowsReady: [Double] = []
        for _ in 0..<20 {
            let start = ContinuousClock.now
            let snapshot = try await provider.list(location, options: .init())
            XCTAssertEqual(snapshot.entries.count, 10_000)
            listing.append(milliseconds(start.duration(to: .now)))
            let freshTab = TabSession(location: location)
            _ = freshTab.apply(snapshot, for: freshTab.requestNavigation(to: location))
            XCTAssertEqual(freshTab.visibleEntries.count, 10_000)
            rowsReady.append(milliseconds(start.duration(to: .now)))
        }
        let workspace = WorkspaceSession(left: location, right: .local(destination))
        let first = workspace.activeTab
        _ = first.apply(warm, for: first.requestNavigation(to: location))
        let second = TabSession(location: location); _ = second.apply(warm, for: second.requestNavigation(to: location))
        workspace.left.tabs.append(second)
        var switching: [Double] = []
        for index in 0..<20 {
            let start = ContinuousClock.now
            workspace.left.activeTabID = index.isMultiple(of: 2) ? first.id : second.id
            XCTAssertEqual(workspace.activeTab.visibleEntries.count, 10_000)
            switching.append(milliseconds(start.duration(to: .now)))
        }
        let plan = try LocalTransferPlanner().plan(.init(kind: .copy, sources: [location], destinationDirectory: .local(destination)))
        let executor = LocalOperationExecutor(journal: .init(directory: f.url.appendingPathComponent("journal")))
        let operation = Task { await executor.execute(plan, cancellation: .init(), resolveConflict: { _ in .init(.skip) }, emit: { _ in }) }
        var scheduling: [Double] = []
        for _ in 0..<20 {
            let start = ContinuousClock.now
            try await Task.sleep(for: .milliseconds(10))
            scheduling.append(max(0, milliseconds(start.duration(to: .now)) - 10))
        }
        let result = await operation.value; XCTAssertEqual(result.state, .completed)
        print("PERFORMANCE warmListingMs=" + describe(listing))
        print("PERFORMANCE firstUsefulModelRowsMs=" + describe(rowsReady))
        print("PERFORMANCE cachedModelSwitchMs=" + describe(switching))
        print("PERFORMANCE mainActorSchedulingLatenessDuringCopyMs=" + describe(scheduling))
    }
    private func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }
    private func describe(_ samples: [Double]) -> String {
        let sorted = samples.sorted()
        return "n=\(samples.count) median=\(sorted[sorted.count / 2]) p95=\(sorted[Int(ceil(Double(sorted.count) * 0.95)) - 1]) max=\(sorted.last!) samples=\(samples)"
    }
}
