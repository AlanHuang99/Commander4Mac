// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

public enum FontChoice: Hashable, Sendable, Codable {
    case system, rounded, serif, monospaced, family(String)
    public static let presets: [FontChoice] = [.system, .rounded, .serif, .monospaced]
    public var title: String {
        switch self {
        case .system: "System"
        case .rounded: "Rounded"
        case .serif: "Serif"
        case .monospaced: "Monospaced"
        case .family(let name): name
        }
    }
    public func validated() -> FontChoice {
        guard case .family(let name) = self else { return self }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return .system }
        return .family(trimmed)
    }
    private enum CodingKeys: String, CodingKey { case kind, family }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try? values.decode(String.self, forKey: .kind) {
        case "rounded": self = .rounded
        case "serif": self = .serif
        case "monospaced": self = .monospaced
        case "family": self = FontChoice.family((try? values.decode(String.self, forKey: .family)) ?? "").validated()
        default: self = .system
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        let kind: String
        switch validated() {
        case .system: kind = "system"
        case .rounded: kind = "rounded"
        case .serif: kind = "serif"
        case .monospaced: kind = "monospaced"
        case .family(let name): kind = "family"; try values.encode(name, forKey: .family)
        }
        try values.encode(kind, forKey: .kind)
    }
}

public struct ViewAppearance: Codable, Equatable, Sendable {
    public var font: FontChoice = .system
    public var textSize: Double = 13
    public var listIconSize: Double = 20
    public var gridIconSize: Double = 64
    public var navigationFont: FontChoice = .system
    public var navigationTextSize: Double = 13
    public var navigationIconSize: Double = 16
    public init() {}
    public func validated() -> Self {
        func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            min(range.upperBound, max(range.lowerBound, value.isFinite ? value : fallback))
        }
        var result = self
        result.font = font.validated(); result.navigationFont = navigationFont.validated()
        result.textSize = clamp(textSize, 10...28, 13)
        result.listIconSize = clamp(listIconSize, 12...40, 20)
        result.gridIconSize = clamp(gridIconSize, 32...160, 64)
        result.navigationTextSize = clamp(navigationTextSize, 10...24, 13)
        result.navigationIconSize = clamp(navigationIconSize, 12...28, 16)
        return result
    }
}
