// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import AppKit
import CommanderCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Keep native presentation at an injectable boundary so offscreen tests can
    // exercise the actual termination delegate without displaying modal UI.
    var presentWorkspaceSaveFailure: (String) -> Void = { detail in
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = "Your workspace could not be saved"
        alert.informativeText = detail + "\n\nCommander4Mac will stay open. Check available disk space and folder access, then try Quit or Check for Updates again."
        alert.addButton(withTitle: "Keep Open"); alert.runModal()
    }
    var confirmCancelFileOperations: () -> Bool = {
        let alert = NSAlert()
        alert.messageText = "File operations are still running"
        alert.informativeText = "Canceling waits until filesystem work has stopped safely before quitting. Completed items are kept."
        alert.addButton(withTitle: "Keep Running"); alert.addButton(withTitle: "Cancel Operations and Quit")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func applicationDidFinishLaunching(_ notification: Notification) { UpdaterController.shared.startIfEligible() }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard !RuntimeIdentity.needsInstallation else { return }
        Task {
            let folders = (try? await BlockingFileWorker.run {
                urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            }) ?? []
            AppServices.shared.acceptIncomingFolders(folders)
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if RuntimeIdentity.needsInstallation {
            NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
        } else if !flag { AppServices.shared.openWorkspaceWindow?() }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !RuntimeIdentity.needsInstallation else { return .terminateNow }
        let services = AppServices.shared
        guard services.activeJobCount > 0 else {
            Task { await finishTermination(sender, services: services) }
            return .terminateLater
        }
        guard confirmCancelFileOperations() else { return .terminateCancel }
        Task {
            for job in services.jobs where !job.state.isTerminal { await services.transferQueue.cancel(jobID: job.id) }
            while services.activeJobCount > 0 { try? await Task.sleep(for: .milliseconds(100)) }
            await finishTermination(sender, services: services)
        }
        return .terminateLater
    }
    private func finishTermination(_ sender: NSApplication, services: AppServices) async {
        guard await services.flushState() else {
            services.updateRelaunch.cancel()
            presentWorkspaceSaveFailure(services.startupDiagnostic ?? "The workspace file could not be written.")
            sender.reply(toApplicationShouldTerminate: false)
            return
        }
        await services.remote.disconnectAll()
        sender.reply(toApplicationShouldTerminate: true)
    }
    func applicationWillTerminate(_ notification: Notification) {
        if !RuntimeIdentity.needsInstallation { AppServices.shared.isTerminating = true }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { RuntimeIdentity.needsInstallation }
}
