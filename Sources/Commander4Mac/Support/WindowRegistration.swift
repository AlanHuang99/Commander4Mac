import SwiftUI
import AppKit

struct WindowRegistration: NSViewRepresentable {
    var controller: WorkspaceController
    func makeNSView(context: Context) -> RegistrationView {
        let view = RegistrationView(); view.controller = controller; return view
    }
    func updateNSView(_ view: RegistrationView, context: Context) { view.controller = controller }
    final class RegistrationView: NSView {
        weak var controller: WorkspaceController?
        private var observer: NotificationToken?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observer = nil
            guard let window else { return }
            controller?.window = window
            if window.isKeyWindow, let controller { controller.services.activate(controller) }
            observer = NotificationToken(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let controller = self?.controller { controller.services.activate(controller) } }
            })
        }
    }
}

private final class NotificationToken: @unchecked Sendable {
    let raw: NSObjectProtocol
    init(_ raw: NSObjectProtocol) { self.raw = raw }
    deinit { NotificationCenter.default.removeObserver(raw) }
}
