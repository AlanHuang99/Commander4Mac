// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.
import AppKit

@MainActor final class TerminationTestApplication: NSApplication {
    var replies: [Bool] = []
    override func reply(toApplicationShouldTerminate shouldTerminate: Bool) { replies.append(shouldTerminate) }
}
@MainActor enum RuntimeIdentity { static let needsInstallation = false }
@MainActor final class UpdaterController { static let shared = UpdaterController(); func startIfEligible() {} }
enum BlockingFileWorker {
    static func run<T: Sendable>(_ work: @Sendable () throws -> T) async rethrows -> T { try work() }
}
@MainActor final class AppServices {
    static let shared = AppServices()
    var activeJobCount = 0
    var startupDiagnostic: String? = "Owned disk-full error"
    var saved = false
    var isTerminating = false
    var openWorkspaceWindow: (() -> Void)?
    var jobs: [TestJob] = []
    let remote = TestRemote(); let transferQueue = TestQueue(); let updateRelaunch = UpdateRelaunchCoordinator()
    func flushState() async -> Bool { saved }
    func acceptIncomingFolders(_ urls: [URL]) {}
}
struct TestJob { let id = UUID(); let state = TestState() }
struct TestState { var isTerminal: Bool { false } }
@MainActor final class TestRemote { var disconnections = 0; func disconnectAll() async { disconnections += 1 } }
@MainActor final class TestQueue { func cancel(jobID: UUID) async { AppServices.shared.activeJobCount = 0 } }

@main @MainActor struct TerminationFailureProbe {
    static func main() async {
        let application = TerminationTestApplication()
        let delegate = AppDelegate(); let services = AppServices.shared
        var errors: [String] = []
        delegate.presentWorkspaceSaveFailure = { errors.append($0) }
        delegate.confirmCancelFileOperations = { true }
        for context in ["ordinary quit", "update termination", "after canceled file operations"] {
            if context == "update termination" {
                services.updateRelaunch.postponeRelaunch(activeOperationCount: 0, flush: { true }, install: {})
                for _ in 0..<200 { if services.updateRelaunch.phase == .installing { break }; await Task.yield() }
                guard services.updateRelaunch.phase == .installing else { print("Update termination was not set up"); exit(1) }
            }
            services.saved = false
            services.activeJobCount = context == "after canceled file operations" ? 1 : 0
            services.jobs = services.activeJobCount > 0 ? [TestJob()] : []
            let oldReplies = application.replies.count; let oldErrors = errors.count
            let result = delegate.applicationShouldTerminate(application)
            guard result == .terminateLater else { print("Quit must finish asynchronously"); exit(1) }
            for _ in 0..<200 { if application.replies.count > oldReplies { break }; await Task.yield() }
            guard application.replies.count == oldReplies + 1, application.replies.last == false,
                  errors.count == oldErrors + 1, errors.last?.contains("Owned disk-full error") == true,
                  services.remote.disconnections == 0, services.updateRelaunch.phase == .idle else { print("Silent or unsafe failed termination: \(context)"); exit(1) }
        }
        services.saved = true; services.activeJobCount = 0
        let oldReplies = application.replies.count; let oldErrors = errors.count
        _ = delegate.applicationShouldTerminate(application)
        for _ in 0..<200 { if application.replies.count > oldReplies { break }; await Task.yield() }
        guard application.replies.last == true, application.replies.count == oldReplies + 1,
              errors.count == oldErrors, services.remote.disconnections == 1 else { print("Quit retry failed after storage recovered"); exit(1) }
        print("Actual AppDelegate save-failure presentation and successful retry passed.")
    }
}
