// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import AppKit
import Combine
import Observation
import Sparkle

@MainActor @Observable final class UpdaterController: NSObject, @preconcurrency SPUUpdaterDelegate {
    static let shared = UpdaterController()
    private(set) var canCheckForUpdates = false
    private(set) var started = false
    var automaticallyChecks = false {
        didSet { if oldValue != automaticallyChecks { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks } }
    }
    var automaticallyDownloads = false {
        didSet { if oldValue != automaticallyDownloads { controller?.updater.automaticallyDownloadsUpdates = automaticallyDownloads } }
    }
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations = Set<AnyCancellable>()
    var isEligible: Bool { RuntimeIdentity.bundleIdentifier == "com.alanhuang.Commander4Mac" && !RuntimeIdentity.needsInstallation }

    func startIfEligible() {
        guard isEligible, !started else { return }
        let value = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        controller = value; started = true
        value.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).sink { [weak self] enabled in
            MainActor.assumeIsolated { self?.canCheckForUpdates = enabled }
        }.store(in: &observations)
        value.updater.publisher(for: \.automaticallyChecksForUpdates).receive(on: RunLoop.main).sink { [weak self] enabled in
            MainActor.assumeIsolated { self?.automaticallyChecks = enabled }
        }.store(in: &observations)
        value.updater.publisher(for: \.automaticallyDownloadsUpdates).receive(on: RunLoop.main).sink { [weak self] enabled in
            MainActor.assumeIsolated { self?.automaticallyDownloads = enabled }
        }.store(in: &observations)
    }
    func checkForUpdates() { guard canCheckForUpdates else { return }; controller?.checkForUpdates(nil) }

    // Sparkle documents delegate callbacks on the main thread. Admission, activity
    // counting and the final state capture therefore share one serialization point.
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                            untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        let services = AppServices.shared
        services.updateRelaunch.postponeRelaunch(activeOperationCount: services.activeJobCount,
            flush: { await services.flushState() }, install: { installHandler() })
        return true
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { AppServices.shared.updateRelaunch.cancel() }
}
