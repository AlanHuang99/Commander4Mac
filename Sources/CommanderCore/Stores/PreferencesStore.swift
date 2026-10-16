import Foundation

public enum AppearanceMode: String, Codable, Sendable, CaseIterable { case system, light, dark }
public struct Preferences: Codable, Equatable, Sendable {
    public var appearance: AppearanceMode = .system
    public var view = ViewOptions()
    public var defaultDestination: OpenDestination = .current
    public var restoreSession = true
    public init() {}
}
public struct PreferencesStore: Sendable {
    public let fileURL: URL
    public init(directory: URL) { fileURL = directory.appendingPathComponent("preferences.json") }
    public func load() -> Preferences {
        guard let data = try? Data(contentsOf: fileURL), var preferences = try? JSONDecoder().decode(Preferences.self, from: data) else { return .init() }
        preferences.view = preferences.view.validated(); return preferences
    }
    public func save(_ preferences: Preferences) throws {
        var value = preferences; value.view = value.view.validated()
        try AtomicFileWriter.write(JSONEncoder().encode(value), to: fileURL)
    }
}
