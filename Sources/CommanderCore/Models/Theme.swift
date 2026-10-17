// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

public struct ThemeColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public init(hex: UInt32) {
        red = Double((hex >> 16) & 255) / 255
        green = Double((hex >> 8) & 255) / 255
        blue = Double(hex & 255) / 255
    }
    public var luminance: Double {
        func linear(_ channel: Double) -> Double { channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    public func contrastRatio(with other: Self) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }
}

public struct ThemePalette: Equatable, Sendable {
    public let background: ThemeColor
    public let chrome: ThemeColor
    public let text: ThemeColor
    public let secondaryText: ThemeColor
    public let accent: ThemeColor
    public let selection: ThemeColor
    public let selectedText: ThemeColor
    fileprivate init(_ colors: [UInt32]) {
        precondition(colors.count == 7)
        background = .init(hex: colors[0]); chrome = .init(hex: colors[1]); text = .init(hex: colors[2])
        secondaryText = .init(hex: colors[3]); accent = .init(hex: colors[4])
        selection = .init(hex: colors[5]); selectedText = .init(hex: colors[6])
    }
}

public enum ThemeID: String, CaseIterable, Codable, Sendable {
    case system, ocean, forest, sand, plum
    public var title: String { rawValue.capitalized }
    public func palette(isDark: Bool) -> ThemePalette? {
        switch (self, isDark) {
        case (.system, _): nil
        case (.ocean, false): .init([0xF5FAFC, 0xE5F0F4, 0x152C38, 0x49626E, 0x126B88, 0xC6E9F4, 0x123346])
        case (.ocean, true): .init([0x0F1F2B, 0x142B39, 0xEDF6FA, 0xB0C5D0, 0x4DB9CF, 0x1D6179, 0xF4FBFE])
        case (.forest, false): .init([0xF5F9F4, 0xE4EEE2, 0x203628, 0x506854, 0x2B7053, 0xCFE8D7, 0x153D28])
        case (.forest, true): .init([0x18241F, 0x213329, 0xEDF7EF, 0xB4CDBD, 0x72B69A, 0x275E48, 0xF1FCF5])
        case (.sand, false): .init([0xFCF8F0, 0xEFE5D3, 0x352B1F, 0x6C5A42, 0x8B5D2E, 0xF0D8B3, 0x503313])
        case (.sand, true): .init([0x29231D, 0x372D24, 0xFCF4E8, 0xD5C0A6, 0xDBAA6D, 0x71512D, 0xFFF7E8])
        case (.plum, false): .init([0xFCF7FD, 0xEEDFF4, 0x36203F, 0x6C5076, 0x87519C, 0xE9D0F3, 0x472553])
        case (.plum, true): .init([0x241E2D, 0x32283E, 0xFAF0FF, 0xCDB8DB, 0xBF95E2, 0x64457C, 0xFFF7FF])
        }
    }
}
