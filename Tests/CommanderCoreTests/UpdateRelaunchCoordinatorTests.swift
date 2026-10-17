// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import XCTest
@testable import CommanderCore

@MainActor final class UpdateRelaunchCoordinatorTests: XCTestCase {
    func testUpdateWaitsForOperationsAndWorkspaceSaveBeforeInstalling() async {
        let coordinator = UpdateRelaunchCoordinator(); let save = ControlledUpdateSave()
        var installs = 0
        coordinator.postponeRelaunch(activeOperationCount: 2, flush: { await save.wait() }, install: { installs += 1 })
        XCTAssertEqual(coordinator.phase, .waitingForOperations); XCTAssertFalse(coordinator.blocksNewOperations)
        coordinator.updateActiveOperationCount(1); XCTAssertEqual(save.calls, 0)
        coordinator.updateActiveOperationCount(0)
        await eventually { save.calls == 1 }
        XCTAssertEqual(installs, 0); XCTAssertTrue(coordinator.blocksNewOperations)
        save.resolve(true); await eventually { installs == 1 }
        XCTAssertEqual(coordinator.phase, .installing); XCTAssertTrue(coordinator.blocksNewOperations)
        coordinator.updateActiveOperationCount(0); await Task.yield(); XCTAssertEqual(installs, 1)
    }

    func testIdleUpdateStillSavesAndDuplicateCallbackCannotInstallTwice() async {
        let coordinator = UpdateRelaunchCoordinator(); let save = ControlledUpdateSave()
        var installs = 0
        coordinator.postponeRelaunch(activeOperationCount: 0, flush: { await save.wait() }, install: { installs += 1 })
        coordinator.postponeRelaunch(activeOperationCount: 0, flush: { XCTFail("duplicate save"); return true }, install: { XCTFail("duplicate install") })
        await eventually { save.calls == 1 }; XCTAssertEqual(installs, 0)
        save.resolve(true); await eventually { installs == 1 }
        coordinator.postponeRelaunch(activeOperationCount: 0, flush: { true }, install: { installs += 1 })
        await Task.yield(); XCTAssertEqual(installs, 1)
    }

    func testCancellationInvalidatesAnAlreadyRunningSave() async {
        let coordinator = UpdateRelaunchCoordinator(); let save = ControlledUpdateSave()
        var installs = 0
        coordinator.postponeRelaunch(activeOperationCount: 0, flush: { await save.wait() }, install: { installs += 1 })
        await eventually { save.calls == 1 }
        coordinator.cancel(); save.resolve(true); await Task.yield()
        XCTAssertEqual(installs, 0); XCTAssertEqual(coordinator.phase, .idle); XCTAssertFalse(coordinator.blocksNewOperations)
    }

    func testLateOperationInvalidatesSaveAndRequiresAnotherDrainAndSave() async {
        let coordinator = UpdateRelaunchCoordinator(); let save = ControlledUpdateSave()
        var installs = 0
        coordinator.postponeRelaunch(activeOperationCount: 0, flush: { await save.wait() }, install: { installs += 1 })
        await eventually { save.calls == 1 }
        coordinator.updateActiveOperationCount(1); save.resolve(true); await Task.yield()
        XCTAssertEqual(installs, 0); XCTAssertEqual(coordinator.phase, .waitingForOperations)
        coordinator.updateActiveOperationCount(0); await eventually { save.calls == 2 }
        save.resolve(true); await eventually { installs == 1 }
    }

    func testFailedSaveKeepsAppRunningAndAllowsExplicitRetry() async {
        let coordinator = UpdateRelaunchCoordinator(); let save = ControlledUpdateSave()
        var installs = 0
        coordinator.postponeRelaunch(activeOperationCount: 0, flush: { await save.wait() }, install: { installs += 1 })
        await eventually { save.calls == 1 }; save.resolve(false)
        await eventually { coordinator.phase == .saveFailed }
        XCTAssertEqual(installs, 0); XCTAssertFalse(coordinator.blocksNewOperations)
        coordinator.retryStateSave(); await eventually { save.calls == 2 }
        save.resolve(true); await eventually { installs == 1 }
        coordinator.cancel(); XCTAssertEqual(coordinator.phase, .idle)
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<100 { if condition() { return }; await Task.yield() }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}

@MainActor private final class ControlledUpdateSave {
    private(set) var calls = 0
    private var waiters: [CheckedContinuation<Bool, Never>] = []
    func wait() async -> Bool { calls += 1; return await withCheckedContinuation { waiters.append($0) } }
    func resolve(_ result: Bool) { precondition(!waiters.isEmpty); waiters.removeFirst().resume(returning: result) }
}
