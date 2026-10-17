// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import SwiftUI
import AppKit
import Quartz
import CommanderCore

enum TableCommand { case open, rename, preview, parent, focusOther, copy, move, newFolder, trash, stage, copyPath, showPackage, copyClipboard, pasteClipboard, moveClipboard }

struct FileTableView: NSViewRepresentable {
    var tab: TabSession
    var revision: UInt64
    var paneID: PaneID
    var destination: FileLocation
    var isActive: Bool
    var onFocus: () -> Void
    var onActivate: (FileEntry) -> Void
    var onCommand: (TableCommand) -> Void
    var renameRequest: UUID?
    var onRename: (FileEntry, String) -> Void
    var onDrop: (TransferRequest) -> Void
    var previewController: QuickLookController
    var focusRequest: UUID?
    func makeCoordinator() -> FileTableCoordinator { FileTableCoordinator(owner: self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = CommanderScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false; scroll.autohidesScrollers = true
        let table = CommanderTableView()
        table.setAccessibilityIdentifier(paneID.rawValue + ".fileTable")
        table.setAccessibilityLabel((paneID == .left ? "Left" : "Right") + " file list")
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.allowsMultipleSelection = true; table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = false
        table.style = .plain; table.columnAutoresizingStyle = .noColumnAutoresizing
        table.intercellSpacing = NSSize(width: 8, height: 0)
        for (key, title, width) in [("name", "Name", 260.0), ("size", "Size", 85.0), ("modified", "Modified", 145.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
            column.title = title; column.width = width; column.minWidth = key == "name" ? 100 : 60
            column.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: true)
            table.addTableColumn(column)
        }
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        table.target = context.coordinator; table.doubleAction = #selector(FileTableCoordinator.activate)
        table.previewController = previewController
        table.onFocus = onFocus; table.onCommand = onCommand
        let menu = NSMenu(); menu.autoenablesItems = false
        for (title, command) in [("Open", TableCommand.open), ("Quick Look", .preview), ("Copy Path", .copyPath), ("Add to Shelf", .stage), ("Copy to Other Pane", .copy), ("Move to Other Pane", .move), ("Rename", .rename), ("New Folder", .newFolder), ("Move to Trash", .trash), ("Show Package Contents", .showPackage)] {
            let item = NSMenuItem(title: title, action: #selector(FileTableCoordinator.contextAction(_:)), keyEquivalent: "")
            item.target = context.coordinator; item.representedObject = CommandBox(command); menu.addItem(item)
        }
        menu.delegate = context.coordinator
        table.menu = menu
        scroll.documentView = table
        context.coordinator.table = table
        context.coordinator.observe(scroll)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.owner = self
        guard let table = coordinator.table else { return }
        table.previewController = previewController
        table.onFocus = onFocus; table.onCommand = onCommand
        for column in table.tableColumns { column.isHidden = !tab.options.visibleColumns.contains(column.identifier.rawValue) }
        table.rowHeight = max(tab.options.textSize + 9, tab.options.listIconSize + 6)
        if coordinator.tabID != tab.id { coordinator.needsRestore = true }
        let savedAnchor = tab.scrollAnchor
        coordinator.synchronizing = true
        if coordinator.entriesRevision != tab.entriesRevision || coordinator.tabID != tab.id || coordinator.options != tab.options {
            coordinator.entries = tab.visibleEntries
            coordinator.entriesRevision = tab.entriesRevision
            coordinator.indexByID = Dictionary(uniqueKeysWithValues: coordinator.entries.enumerated().map { ($0.element.id, $0.offset) })
            coordinator.tabID = tab.id; coordinator.options = tab.options
            table.reloadData()
        }
        let indexes = IndexSet(tab.selection.compactMap { coordinator.indexByID[$0] })
        if table.selectedRowIndexes != indexes { table.selectRowIndexes(indexes, byExtendingSelection: false) }
        if coordinator.needsRestore, !coordinator.entries.isEmpty {
            if let savedAnchor, let index = coordinator.entries.firstIndex(where: { $0.id == savedAnchor }) {
                table.scroll(NSPoint(x: 0, y: table.rect(ofRow: index).minY))
            }
            coordinator.needsRestore = false
        }
        table.setAccessibilityLabel((paneID == .left ? "Left" : "Right") + (isActive ? " active file list" : " file list"))
        table.layoutSubtreeIfNeeded()
        RuntimeMetrics.rendered(tab, lastGeneration: &coordinator.renderedGeneration)
        coordinator.synchronizing = false
        if isActive && !coordinator.wasActive { table.window?.makeFirstResponder(table) }
        if isActive, let focusRequest, coordinator.lastFocusRequest != focusRequest {
            coordinator.lastFocusRequest = focusRequest; table.window?.makeFirstResponder(table)
        }
        coordinator.wasActive = isActive
        if let renameRequest, coordinator.lastRenameRequest != renameRequest, isActive {
            coordinator.lastRenameRequest = renameRequest
            coordinator.beginRename()
        }
    }
}

final class CommandBox: NSObject { let command: TableCommand; init(_ command: TableCommand) { self.command = command } }

final class CommanderTableView: NSTableView {
    weak var previewController: QuickLookController?
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { previewController?.hasItems == true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = previewController; panel.delegate = previewController }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil; panel.delegate = nil }
    @objc func copy(_ sender: Any?) { onCommand?(.copyClipboard) }
    @objc func paste(_ sender: Any?) { onCommand?(.pasteClipboard) }
    var onFocus: (() -> Void)?
    var onCommand: ((TableCommand) -> Void)?
    override func becomeFirstResponder() -> Bool { let accepted = super.becomeFirstResponder(); if accepted { onFocus?() }; return accepted }
    override func rightMouseDown(with event: NSEvent) {
        onFocus?()
        let index = row(at: convert(event.locationInWindow, from: nil))
        if index >= 0 && !selectedRowIndexes.contains(index) { selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        super.rightMouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        RuntimeMetrics.record("keyDelivery", since: event.timestamp)
        if currentEditor() != nil { super.keyDown(with: event); return }
        if let command = FileTableCommandHandler.command(for: event) { onCommand?(command) }
        else { super.keyDown(with: event) }
    }
}

@MainActor final class CommanderScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let table = documentView as? NSTableView, table.tableColumns.count == 3 else { return }
        let width = max(280, contentSize.width)
        let sizeWidth: CGFloat = 67
        let dateWidth: CGFloat = width > 430 ? 145 : 112
        let usedSize: CGFloat = table.tableColumns[1].isHidden ? 0 : sizeWidth
        let usedDate: CGFloat = table.tableColumns[2].isHidden ? 0 : dateWidth
        let widths = [max(100, width - usedSize - usedDate), sizeWidth, dateWidth]
        for (column, target) in zip(table.tableColumns, widths) where abs(column.width - target) > 0.5 { column.width = target }
        if abs(table.frame.width - width) > 0.5 { table.setFrameSize(NSSize(width: width, height: table.frame.height)) }
        if contentView.bounds.origin.x != 0 { contentView.scroll(to: NSPoint(x: 0, y: contentView.bounds.origin.y)) }
    }
}

extension TableCommand {
    @MainActor func isSupported(in browser: FileTableView) -> Bool {
        let local = browser.tab.location.isLocal
        switch self {
        case .preview, .trash, .stage, .copyClipboard: return local
        case .move: return local && browser.destination.isLocal
        case .moveClipboard: return local
        case .copy:
            return TransferCapabilities.canTransfer(.copy, from: browser.tab.location, to: browser.destination, entries: browser.tab.selectedEntries)
        case .showPackage: return local && browser.tab.selectedEntries.first?.kind == .package
        default: return true
        }
    }
}
