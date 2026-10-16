import AppKit
import CommanderCore

@MainActor enum SystemFileActions {
    static func open(_ locations: [FileLocation]) -> Bool {
        locations.reduce(true) { result, location in NSWorkspace.shared.open(location.url) && result }
    }
    static func applications(for location: FileLocation) -> [URL] { NSWorkspace.shared.urlsForApplications(toOpen: location.url) }
    static func open(_ locations: [FileLocation], with application: URL, onError: @escaping @MainActor (String) -> Void) {
        NSWorkspace.shared.open(locations.map(\.url), withApplicationAt: application, configuration: .init()) { _, error in
            if let error { Task { @MainActor in onError(error.localizedDescription) } }
        }
    }
}
