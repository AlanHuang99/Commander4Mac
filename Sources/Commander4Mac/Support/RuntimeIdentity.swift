import Foundation

struct RuntimeIdentity {
    let bundleIdentifier: String
    let bundleURL: URL
    let executableURL: URL?
    static func current() -> RuntimeIdentity {
        RuntimeIdentity(bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
                        bundleURL: Bundle.main.bundleURL, executableURL: Bundle.main.executableURL)
    }
}
