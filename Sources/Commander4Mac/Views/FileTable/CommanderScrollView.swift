// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import AppKit

@MainActor final class CommanderScrollView: NSScrollView {
    var fileTextSize: Double = 13
    var listIconSize: Double = 20
    override func layout() {
        super.layout()
        guard let table = documentView as? NSTableView, table.tableColumns.count == 3 else { return }
        let viewport = max(280, contentSize.width)
        let scale = max(1, fileTextSize / 13)
        let sizeWidth: CGFloat = ceil(67 * scale)
        let dateWidth: CGFloat = ceil((viewport > 430 ? 145 : 112) * scale)
        let usedSize: CGFloat = table.tableColumns[1].isHidden ? 0 : sizeWidth
        let usedDate: CGFloat = table.tableColumns[2].isHidden ? 0 : dateWidth
        let minimumName = max(100, listIconSize + fileTextSize * 5 + 20)
        let spacing = CGFloat(table.tableColumns.filter { !$0.isHidden }.count) * table.intercellSpacing.width
        let width = max(viewport, minimumName + usedSize + usedDate + spacing)
        let widths = [ceil(max(minimumName, width - usedSize - usedDate - spacing)), sizeWidth, dateWidth]
        for (column, target) in zip(table.tableColumns, widths) where abs(column.width - target) > 0.5 { column.width = target }
        // AppKit includes intercell spacing and pixel rounding in these rects.
        // Use the actual extents so the final cell remains reachable by scrolling.
        let rightEdge = table.tableColumns.indices.filter { !table.tableColumns[$0].isHidden }
            .map { table.rect(ofColumn: $0).maxX }.max() ?? 0
        let documentWidth = max(viewport, ceil(rightEdge))
        if abs(table.frame.width - documentWidth) > 0.5 { table.setFrameSize(NSSize(width: documentWidth, height: table.frame.height)) }
        if documentWidth <= contentSize.width, contentView.bounds.origin.x != 0 { contentView.scroll(to: NSPoint(x: 0, y: contentView.bounds.origin.y)) }
    }
}
