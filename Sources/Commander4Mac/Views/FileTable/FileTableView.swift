import SwiftUI
import AppKit
import CommanderCore

enum TableCommand { case open, rename, preview, parent, focusOther, copy, move, newFolder, trash, stage, copyPath, showPackage, copyClipboard, pasteClipboard, moveClipboard }

struct FileTableView: NSViewRepresentable {
    var tab: TabSession
    var paneID: PaneID
    var isActive: Bool
    var onFocus: () -> Void
    var onActivate: (FileEntry) -> Void
    var onCommand: (TableCommand) -> Void
    func makeCoordinator() -> FileTableCoordinator { FileTableCoordinator(owner: self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        let table = CommanderTableView()
        table.setAccessibilityIdentifier(paneID.rawValue + ".fileTable")
        table.setAccessibilityLabel((paneID == .left ? "Left" : "Right") + " file list")
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.allowsMultipleSelection = true; table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = false
        table.style = .plain; table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.intercellSpacing = NSSize(width: 8, height: 0)
        for (key, title, width) in [("name", "Name", 260.0), ("size", "Size", 85.0), ("modified", "Modified", 145.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key))
            column.title = title; column.width = width; column.minWidth = key == "name" ? 140 : 65
            column.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: true)
            table.addTableColumn(column)
        }
        table.target = context.coordinator; table.doubleAction = #selector(FileTableCoordinator.activate)
        table.onFocus = onFocus; table.onCommand = onCommand
        let menu = NSMenu()
        for (title, command) in [("Open", TableCommand.open), ("Quick Look", .preview), ("Copy Path", .copyPath)] {
            let item = NSMenuItem(title: title, action: #selector(FileTableCoordinator.contextAction(_:)), keyEquivalent: "")
            item.target = context.coordinator; item.representedObject = CommandBox(command); menu.addItem(item)
        }
        table.menu = menu
        scroll.documentView = table
        context.coordinator.table = table
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.owner = self
        guard let table = coordinator.table else { return }
        table.onFocus = onFocus; table.onCommand = onCommand
        table.rowHeight = max(tab.options.textSize + 9, tab.options.listIconSize + 6)
        coordinator.synchronizing = true
        if coordinator.entries != tab.visibleEntries || coordinator.tabID != tab.id || coordinator.options != tab.options {
            coordinator.entries = tab.visibleEntries; coordinator.tabID = tab.id; coordinator.options = tab.options
            table.reloadData()
        }
        let indexes = IndexSet(coordinator.entries.indices.filter { tab.selection.contains(coordinator.entries[$0].id) })
        if table.selectedRowIndexes != indexes { table.selectRowIndexes(indexes, byExtendingSelection: false) }
        coordinator.synchronizing = false
        if isActive && !coordinator.wasActive { table.window?.makeFirstResponder(table) }
        coordinator.wasActive = isActive
    }
}

final class CommandBox: NSObject { let command: TableCommand; init(_ command: TableCommand) { self.command = command } }

final class CommanderTableView: NSTableView {
    var onFocus: (() -> Void)?
    var onCommand: ((TableCommand) -> Void)?
    override func mouseDown(with event: NSEvent) { onFocus?(); super.mouseDown(with: event) }
    override func rightMouseDown(with event: NSEvent) {
        onFocus?()
        let index = row(at: convert(event.locationInWindow, from: nil))
        if index >= 0 && !selectedRowIndexes.contains(index) { selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        super.rightMouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if currentEditor() != nil { super.keyDown(with: event); return }
        switch event.keyCode {
        case 48: onCommand?(.focusOther)
        case 36: onCommand?(.rename)
        case 49: onCommand?(.preview)
        case 51 where event.modifierFlags.contains(.command): onCommand?(.trash)
        case 116: onCommand?(.copy)
        case 117: onCommand?(.move)
        case 98: onCommand?(.newFolder)
        default: super.keyDown(with: event)
        }
    }
}
