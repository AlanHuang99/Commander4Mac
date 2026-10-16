import AppKit
import CommanderCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task {
            let folders = (try? await BlockingFileWorker.run {
                urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            }) ?? []
            AppServices.shared.acceptIncomingFolders(folders)
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppServices.shared.openWorkspaceWindow?() }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let services = AppServices.shared
        guard services.activeJobCount > 0 else {
            Task { await services.flushState(); await services.remote.disconnectAll(); sender.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        }
        let alert = NSAlert()
        alert.messageText = "File operations are still running"
        alert.informativeText = "Canceling waits until filesystem work has stopped safely before quitting. Completed items are kept."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Cancel Operations and Quit")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        Task {
            for job in services.jobs where !job.state.isTerminal { await services.transferQueue.cancel(jobID: job.id) }
            while services.activeJobCount > 0 { try? await Task.sleep(for: .milliseconds(100)) }
            await services.flushState()
            await services.remote.disconnectAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        AppServices.shared.isTerminating = true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
