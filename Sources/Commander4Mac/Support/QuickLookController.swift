// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import AppKit
import Quartz
import CommanderCore

@MainActor final class QuickLookController: NSObject, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    private var items: [NSURL] = []
    var hasItems: Bool { !items.isEmpty }
    func present(_ locations: [FileLocation], selectedIndex: Int = 0) {
        guard !locations.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible { panel.orderOut(nil); return }
        items = locations.map { $0.url as NSURL }
        panel.updateController()
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData(); panel.currentPreviewItemIndex = min(max(0, selectedIndex), items.count - 1)
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { items.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        items.indices.contains(index) ? items[index] : nil
    }
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, [UInt16(49), UInt16(53)].contains(event.keyCode) else { return false }
        panel.orderOut(nil); return true
    }
}
