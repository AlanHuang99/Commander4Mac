// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import AppKit
import SwiftUI
import CommanderCore

extension ThemeColor {
    var nsColor: NSColor { .init(srgbRed: red, green: green, blue: blue, alpha: 1) }
    var color: Color { Color(nsColor: nsColor) }
}

@MainActor enum AppearanceFont {
    private static let cache: NSCache<NSString, NSFont> = { let value = NSCache<NSString, NSFont>(); value.countLimit = 256; return value }()
    static let installedFamilies = NSFontManager.shared.availableFontFamilies.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    static func resolve(_ choice: FontChoice, size: Double) -> NSFont {
        let valid = choice.validated()
        let key = "\(valid)-\(size)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let base = NSFont.systemFont(ofSize: size)
        let font: NSFont
        switch valid {
        case .system: font = base
        case .monospaced: font = .monospacedSystemFont(ofSize: size, weight: .regular)
        case .rounded, .serif:
            let descriptor = base.fontDescriptor.withDesign(valid == .rounded ? .rounded : .serif) ?? base.fontDescriptor
            font = NSFont(descriptor: descriptor, size: size) ?? base
        case .family(let name): font = NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size) ?? base
        }
        cache.setObject(font, forKey: key); return font
    }
    static func lineHeight(_ font: NSFont) -> Double { ceil(font.ascender - font.descender + max(0, font.leading)) }
}

@MainActor final class ThemedTableRow: NSTableRowView {
    var palette: ThemePalette? { didSet { needsDisplay = true; updateText() } }
    override var isSelected: Bool { didSet { updateText() } }
    override func didAddSubview(_ subview: NSView) { super.didAddSubview(subview); updateText() }
    override func drawSelection(in dirtyRect: NSRect) {
        guard let palette else { super.drawSelection(in: dirtyRect); return }
        palette.selection.nsColor.setFill(); bounds.fill()
    }
    private func updateText() {
        guard let palette else { return }
        for case let cell as NSTableCellView in subviews {
            cell.textField?.textColor = isSelected ? palette.selectedText.nsColor :
                (cell.identifier?.rawValue == "name" ? palette.text.nsColor : palette.secondaryText.nsColor)
        }
    }
}
