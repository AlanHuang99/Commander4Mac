import SwiftUI
import AppKit
import CommanderCore

private struct WorkspaceFocusKey: FocusedValueKey { typealias Value = WorkspaceController }
extension FocusedValues {
    var workspaceController: WorkspaceController? {
        get { self[WorkspaceFocusKey.self] }
        set { self[WorkspaceFocusKey.self] = newValue }
    }
}
struct AppCommands: Commands {
    @FocusedValue(\.workspaceController) private var focusedController
    private var controller: WorkspaceController? {
        guard let controller = focusedController, controller.window?.isKeyWindow == true else { return nil }
        return controller
    }
    @Environment(\.openWindow) private var openWindow
    private var hasSelection: Bool { controller?.workspace.activeTab.selection.isEmpty == false && controller?.isEditingText == false && controller?.workspace.activeTab.failure == nil }
    private var localSelection: Bool { hasSelection && controller?.workspace.activeTab.location.isLocal == true }
    private var canMove: Bool {
        guard let controller else { return false }
        return localSelection && controller.workspace.pane(controller.workspace.activePane.opposite).activeTab.location.isLocal
    }
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "workspace") }.keyboardShortcut("n")
            Button("New Tab") { controller?.newTab() }.keyboardShortcut("t").disabled(controller == nil)
            Button(controller == nil ? "Close Window" : "Close Tab") {
                if let controller { controller.closeTab() } else { NSApp.keyWindow?.performClose(nil) }
            }
            Button("Close Window") { if let controller { controller.closeWindow() } else { NSApp.keyWindow?.performClose(nil) } }.keyboardShortcut("w", modifiers: [.command, .shift])
        }
        CommandGroup(before: .saveItem) {
            Button("Connect to Server…") { controller?.manageConnection() }.keyboardShortcut("k").disabled(controller == nil)

            Button("Open") { controller?.openSelection() }.keyboardShortcut("o").disabled(!hasSelection)
            Button("Open Folder…") { controller?.chooseFolder() }.keyboardShortcut("g", modifiers: [.command, .shift]).disabled(controller == nil)
            Button("New Folder…") { controller?.newFolder() }.keyboardShortcut("n", modifiers: [.command, .shift]).disabled(controller == nil)
            Button("Rename") { controller?.tableCommand(.rename, pane: controller!.workspace.activePane) }.disabled(!hasSelection)
            Button("Quick Look") { controller?.previewSelection() }.disabled(!localSelection)
            Button("Move to Trash") { controller?.trashSelection() }.keyboardShortcut(.delete, modifiers: .command).disabled(!localSelection)
        }
        CommandGroup(after: .pasteboard) {
            Button("Move Item Here") { controller?.paste(.move) }.keyboardShortcut("v", modifiers: [.command, .option]).disabled(controller == nil || controller?.isEditingText == true)
            Button("Copy Path") { controller?.tableCommand(.copyPath, pane: controller!.workspace.activePane) }.keyboardShortcut("c", modifiers: [.command, .option]).disabled(!hasSelection)
            Button("Add to Shelf") { controller?.stageSelection() }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(!localSelection)
        }
        CommandMenu("Pane") {
            Button("Copy to Other Pane") { controller?.transferSelection(.copy, from: controller!.workspace.activePane) }.keyboardShortcut(KeyEquivalent("\u{F708}"), modifiers: []).disabled(!hasSelection)
            Button("Move to Other Pane") { controller?.transferSelection(.move, from: controller!.workspace.activePane) }.keyboardShortcut(KeyEquivalent("\u{F709}"), modifiers: []).disabled(!canMove)
            Divider()
            Button("Go to Path") { controller?.focus(.path) }.keyboardShortcut("l").disabled(controller == nil)
            Button("Filter Folder") { controller?.focus(.filter) }.keyboardShortcut("f").disabled(controller == nil)
            Button("Parent Folder") { controller?.tableCommand(.parent, pane: controller!.workspace.activePane) }.keyboardShortcut(.upArrow, modifiers: .command).disabled(controller == nil)
            Button("Back") { if let c = controller { c.history(c.workspace.activePane, forward: false) } }.keyboardShortcut("[").disabled(controller?.workspace.activeTab.canGoBack != true)
            Button("Forward") { if let c = controller { c.history(c.workspace.activePane, forward: true) } }.keyboardShortcut("]").disabled(controller?.workspace.activeTab.canGoForward != true)
            Button("Refresh") { if let c = controller { Task { await c.refresh(c.workspace.activePane) } } }.keyboardShortcut("r").disabled(controller == nil)
            Divider()
            Button("Toggle Shelf") { controller?.shelfVisible.toggle() }.disabled(controller == nil)
            Button("Toggle Activity") { controller?.activityVisible.toggle() }.disabled(controller == nil)
        }
    }
}
