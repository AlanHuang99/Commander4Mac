// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.
import AppKit

@main @MainActor struct NativeTableGeometryProbe {
    static func main() {
        _ = NSApplication.shared
        var failures: [String] = []
        for viewport in [320.0, 380, 600, 1000] {
            for (text, icons) in [(10.0, 12.0), (13, 20), (28, 40)] {
                for hidden in [Set<Int>(), [1], [2], [1, 2]] {
                    let scroll = CommanderScrollView(frame: NSRect(x: 0, y: 0, width: viewport, height: 400))
                    scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
                    scroll.fileTextSize = text; scroll.listIconSize = icons
                    let table = NSTableView(frame: NSRect(x: 0, y: 0, width: viewport, height: 1000))
                    table.style = .plain; table.columnAutoresizingStyle = .noColumnAutoresizing; table.intercellSpacing = NSSize(width: 8, height: 0)
                    for index in 0..<3 {
                        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column\(index)"))
                        column.width = [260, 85, 145][index]; column.minWidth = index == 0 ? 100 : 60
                        table.addTableColumn(column); column.isHidden = hidden.contains(index)
                    }
                    scroll.documentView = table
                    for _ in 0..<3 { scroll.layoutSubtreeIfNeeded(); scroll.layout() }
                    let last = (0..<3).filter { !hidden.contains($0) }.last!
                    let edge = table.rect(ofColumn: last).maxX
                    if edge > table.frame.width + 0.5 {
                        failures.append("Clipped last column: viewport\(viewport) text\(text) icons\(icons) hidden\(hidden.sorted()) document\(table.frame.width) edge\(edge)")
                    }
                    scroll.contentView.scroll(to: NSPoint(x: max(0, table.frame.width - scroll.contentSize.width), y: 0))
                    if scroll.contentView.bounds.maxX + 0.5 < edge { failures.append("Last column remains unreachable after scrolling") }
                    if text <= 13, viewport >= 380, table.frame.width > scroll.contentSize.width + 0.5 { failures.append("Normal-size columns unnecessarily scroll horizontally") }
                }
            }
        }
        if !failures.isEmpty { print(failures.joined(separator: "\n")); exit(1) }
        print("48 native table geometry/hidden-column configurations passed.")
    }
}
