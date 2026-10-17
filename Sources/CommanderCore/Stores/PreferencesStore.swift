// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

public enum AppearanceMode: String, Codable, Sendable, CaseIterable { case system, light, dark }
public struct Preferences: Codable, Equatable, Sendable {
    public var appearance: AppearanceMode = .system
    public var view = ViewOptions()
    public var defaultDestination: OpenDestination = .current
    public var restoreSession = true
    public var shareAppearanceChanges = true
    public var theme: ThemeID = .system
    public var sidebarWidth: Double = 220
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case appearance, view, defaultDestination, restoreSession, shareAppearanceChanges, theme, sidebarWidth
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appearance = (try? values.decodeIfPresent(AppearanceMode.self, forKey: .appearance)) ?? .system
        view = (try? values.decodeIfPresent(ViewOptions.self, forKey: .view)) ?? .init()
        defaultDestination = (try? values.decodeIfPresent(OpenDestination.self, forKey: .defaultDestination)) ?? .current
        restoreSession = (try? values.decodeIfPresent(Bool.self, forKey: .restoreSession)) ?? true
        shareAppearanceChanges = (try? values.decodeIfPresent(Bool.self, forKey: .shareAppearanceChanges)) ?? true
        theme = (try? values.decodeIfPresent(ThemeID.self, forKey: .theme)) ?? .system
        sidebarWidth = (try? values.decodeIfPresent(Double.self, forKey: .sidebarWidth)) ?? 220
        self = validated()
    }
    public func validated() -> Self {
        var result = self
        result.view = view.validated()
        result.sidebarWidth = min(320, max(180, sidebarWidth.isFinite ? sidebarWidth : 220))
        return result
    }
}
public struct PreferencesStore: Sendable {
    public let fileURL: URL
    public init(directory: URL) { fileURL = directory.appendingPathComponent("preferences.json") }
    public func load() -> Preferences {
        guard let data = try? Data(contentsOf: fileURL), var preferences = try? JSONDecoder().decode(Preferences.self, from: data) else { return .init() }
        preferences = preferences.validated(); return preferences
    }
    public func save(_ preferences: Preferences) throws {
        let value = preferences.validated()
        try AtomicFileWriter.write(JSONEncoder().encode(value), to: fileURL)
    }
}
