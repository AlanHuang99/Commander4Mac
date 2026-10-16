import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let services = AppServices.shared
        guard services.activeJobCount > 0 else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "File operations are still running"
        alert.informativeText = "Canceling waits until filesystem work has stopped safely before quitting. Completed items are kept."
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Cancel Operations and Quit")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        Task {
            for job in services.jobs where !job.state.isTerminal { await services.transferQueue.cancel(jobID: job.id) }
            while services.activeJobCount > 0 { try? await Task.sleep(for: .milliseconds(100)) }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) {
        AppServices.shared.isTerminating = true
        AppServices.shared.saveNow()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
