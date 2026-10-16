import Foundation

/// Installation guidance only. This never grants access or claims FDA is enabled.
public enum InstallationLocation {
    public static func isInstalled(_ bundleURL: URL, homeDirectory: URL) -> Bool {
        guard bundleURL.isFileURL, bundleURL.host == nil || bundleURL.host == "" || bundleURL.host == "localhost" else { return false }
        let path = bundleURL.standardizedFileURL.path
        let userApplications = homeDirectory.appendingPathComponent("Applications", isDirectory: true).standardizedFileURL.path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/")
    }
}
