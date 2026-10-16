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
    var renameRequest: UUID?
    var onRename: (FileEntry, String) -> Void
    var onDrop: (TransferRequest) -> Void
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
        table.onFocus = onFocus; table.onCommand = onCommand
        let menu = NSMenu()
        for (title, command) in [("Open", TableCommand.open), ("Quick Look", .preview), ("Copy Path", .copyPath), ("Add to Shelf", .stage), ("Copy to Other Pane", .copy), ("Move to Other Pane", .move), ("Rename", .rename), ("New Folder", .newFolder), ("Move to Trash", .trash)] {
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
        if let renameRequest, coordinator.lastRenameRequest != renameRequest, isActive {
            coordinator.lastRenameRequest = renameRequest
            coordinator.beginRename()
        }
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
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": onCommand?(.copyClipboard); return
            case "v": onCommand?(event.modifierFlags.contains(.option) ? .moveClipboard : .pasteClipboard); return
            default: break
            }
        }
        switch event.keyCode {
        case 48: onCommand?(.focusOther)
        case 36: onCommand?(.rename)
        case 49: onCommand?(.preview)
        case 51 where event.modifierFlags.contains(.command): onCommand?(.trash)
        case 96: onCommand?(.copy)
        case 97: onCommand?(.move)
        case 98: onCommand?(.newFolder)
        default: super.keyDown(with: event)
        }
    }
}

@MainActor final class CommanderScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let table = documentView as? NSTableView, table.tableColumns.count == 3 else { return }
        let width = max(280, contentSize.width)
        let sizeWidth: CGFloat = 67
        let dateWidth: CGFloat = width > 430 ? 145 : 112
        let widths = [max(100, width - sizeWidth - dateWidth), sizeWidth, dateWidth]
        for (column, target) in zip(table.tableColumns, widths) where abs(column.width - target) > 0.5 { column.width = target }
        if abs(table.frame.width - width) > 0.5 { table.setFrameSize(NSSize(width: width, height: table.frame.height)) }
        if contentView.bounds.origin.x != 0 { contentView.scroll(to: NSPoint(x: 0, y: contentView.bounds.origin.y)) }
    }
}
