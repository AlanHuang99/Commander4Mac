import SwiftUI
import AppKit

struct WindowRegistration: NSViewRepresentable {
    var controller: WorkspaceController
    func makeNSView(context: Context) -> RegistrationView {
        let view = RegistrationView(); view.controller = controller; return view
    }
    func updateNSView(_ view: RegistrationView, context: Context) { view.controller = controller; view.installCloseDelegate() }
    final class RegistrationView: NSView {
        weak var controller: WorkspaceController?
        private var observer: NotificationToken?
        private var closeDelegate: FileWindowCloseDelegate?
        private var closeKeyMonitor: Any?
        private weak var delegateWindow: NSWindow?
        private func detachDelegate() {
            if let window = delegateWindow, let proxy = closeDelegate, window.delegate === proxy { window.delegate = proxy.forwardedDelegate }
            closeDelegate = nil; delegateWindow = nil
        }
        isolated deinit {
            detachDelegate()
            if let closeKeyMonitor { NSEvent.removeMonitor(closeKeyMonitor) }
        }
        func installCloseDelegate() {
            guard let window, let controller else { return }
            controller.window = window
            if let closeDelegate, window.delegate === closeDelegate { return }
            detachDelegate()
            let proxy = FileWindowCloseDelegate(controller: controller, forwarding: window.delegate)
            closeDelegate = proxy; delegateWindow = window; window.delegate = proxy
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); detachDelegate(); observer = nil
            if let closeKeyMonitor { NSEvent.removeMonitor(closeKeyMonitor); self.closeKeyMonitor = nil }
            guard let window else { return }
            installCloseDelegate()
            // SwiftUI can reinstall its window delegate after a tab updates. Route the
            // tab shortcut before AppKit dispatches the built-in window Close command.
            closeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window,
                      event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
                      event.charactersIgnoringModifiers?.lowercased() == "w", let controller = self.controller else { return event }
                controller.closeTab()
                return nil
            }
            if window.isKeyWindow, let controller { controller.services.activate(controller) }
            observer = NotificationToken(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.installCloseDelegate()
                    if let controller = self?.controller { controller.services.activate(controller) }
                }
            })
        }
    }
}
final class NotificationToken: @unchecked Sendable {
    let raw: NSObjectProtocol
    init(_ raw: NSObjectProtocol) { self.raw = raw }
    deinit { NotificationCenter.default.removeObserver(raw) }
}

/// SwiftUI's built-in Close item targets NSWindow directly, before a content responder can handle it.
/// Forward every other delegate callback to SwiftUI's existing delegate.
@MainActor private final class FileWindowCloseDelegate: NSObject, NSWindowDelegate {
    weak var controller: WorkspaceController?
    // Objective-C capability queries may arrive outside actor isolation; this weak reference is only forwarded.
    nonisolated(unsafe) weak var forwardedDelegate: (any NSWindowDelegate)?
    init(controller: WorkspaceController, forwarding delegate: (any NSWindowDelegate)?) {
        self.controller = controller; forwardedDelegate = delegate
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let controller, !controller.forceWindowClose {
            let event = NSApp.currentEvent
            var redButtonClick = sender.standardWindowButton(.closeButton)?.isHighlighted == true
            if let event, event.window === sender, event.type == .leftMouseUp || event.type == .leftMouseDown,
               let button = sender.standardWindowButton(.closeButton) {
                redButtonClick = redButtonClick || button.bounds.contains(button.convert(event.locationInWindow, from: nil))
            }
            let closeAllShortcut = event?.type == .keyDown && event?.modifierFlags.contains([.command, .option]) == true && event?.charactersIgnoringModifiers?.lowercased() == "w"
            if !redButtonClick && !closeAllShortcut {
                let pane = controller.workspace.pane(controller.workspace.activePane)
                if pane.activeTab.pin.isPinned { return false }
                if pane.tabs.count > 1 {
                    _ = pane.close(tabID: pane.activeTabID); controller.services.saveSoon(); return false
                }
            }
        }
        return forwardedDelegate?.windowShouldClose?(sender) ?? true
    }
    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || forwardedDelegate?.responds(to: selector) == true
    }
    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        if forwardedDelegate?.responds(to: selector) == true { return forwardedDelegate }
        return super.forwardingTarget(for: selector)
    }
}
