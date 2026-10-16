import AppKit
import CommanderCore
import UniformTypeIdentifiers

@MainActor
final class FileTableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
    var owner: FileTableView
    weak var table: CommanderTableView?
    var entries: [FileEntry] = []
    var entriesRevision: UInt64?
    var indexByID: [EntryID: Int] = [:]
    var tabID: UUID?
    var options = ViewOptions()
    var synchronizing = false
    var wasActive = false
    var renderedGeneration: UInt64?
    var needsRestore = true
    private var scrollObserver: NotificationToken?
    func observe(_ scroll: NSScrollView) {
        scroll.contentView.postsBoundsChangedNotifications = true
        scrollObserver = NotificationToken(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.synchronizing, let table = self.table else { return }
                let index = table.rows(in: table.visibleRect).location
                if self.entries.indices.contains(index) { self.owner.tab.scrollAnchor = self.entries[index].id }
            }
        })
    }
    var lastFocusRequest: UUID?
    var lastRenameRequest: UUID?
    private var editingEntry: FileEntry?

    init(owner: FileTableView) { self.owner = owner }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard entries.indices.contains(row), let column else { return nil }
        let entry = entries[row]
        let key = column.identifier.rawValue
        let identifier = NSUserInterfaceItemIdentifier(key)
        let cell: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView { cell = existing }
        else {
            cell = NSTableCellView(); cell.identifier = identifier
            let text = NSTextField(labelWithString: "")
            text.translatesAutoresizingMaskIntoConstraints = false; text.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(text); cell.textField = text
            if key == "name" {
                let icon = NSImageView(); icon.translatesAutoresizingMaskIntoConstraints = false; icon.imageScaling = .scaleProportionallyDown
                cell.addSubview(icon); cell.imageView = icon
                NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: 20), icon.heightAnchor.constraint(equalToConstant: 20),
                    text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7)])
            } else { text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3).isActive = true }
            NSLayoutConstraint.activate([text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        }
        cell.textField?.font = .systemFont(ofSize: options.textSize)
        cell.textField?.textColor = key == "name" ? .labelColor : .secondaryLabelColor
        cell.textField?.alignment = key == "size" ? .right : .left
        switch key {
        case "name":
            cell.textField?.stringValue = entry.name; cell.toolTip = entry.location.url.path
            cell.imageView?.image = FileIconCache.shared.icon(for: entry)
            cell.imageView?.constraints.filter { $0.firstAttribute == .width || $0.firstAttribute == .height }.forEach { $0.constant = options.listIconSize }
        case "size": cell.textField?.stringValue = entry.byteSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "–"
        case "modified": cell.textField?.stringValue = entry.modificationDate?.formatted(date: .abbreviated, time: .shortened) ?? ""
        default: break
        }
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !synchronizing, let table else { return }
        owner.tab.selection = Set(table.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0].id : nil })
    }
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let sort = tableView.sortDescriptors.first, let key = sort.key, let column = SortColumn(rawValue: key) else { return }
        owner.tab.options.sortColumn = column; owner.tab.options.ascending = sort.ascending
    }
    func beginRename() {
        guard let table, table.selectedRowIndexes.count == 1, entries.indices.contains(table.selectedRow),
              let cell = table.view(atColumn: 0, row: table.selectedRow, makeIfNecessary: true) as? NSTableCellView,
              let field = cell.textField else { return }
        editingEntry = entries[table.selectedRow]
        field.isEditable = true; field.isSelectable = true; field.delegate = self
        table.scrollRowToVisible(table.selectedRow)
        table.editColumn(0, row: table.selectedRow, with: nil, select: true)
    }
    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool { editingEntry != nil && tableColumn?.identifier.rawValue == "name" }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let entry = editingEntry else { return }
        let canceled = (notification.userInfo?["NSTextMovement"] as? Int) == NSTextMovement.cancel.rawValue
        let name = field.stringValue
        field.isEditable = false; field.isSelectable = false; field.delegate = nil; editingEntry = nil
        field.stringValue = entry.name
        if !canceled && name != entry.name { owner.onRename(entry, name) }
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard entries.indices.contains(row), entries[row].location.isLocal else { return nil }
        return entries[row].location.url as NSURL
    }
    private func dropDestination(row: Int, operation: NSTableView.DropOperation) -> FileLocation? {
        if operation == .on && entries.indices.contains(row) { return entries[row].isDirectory ? entries[row].location : nil }
        return owner.tab.location
    }
    private func dropKind(_ info: any NSDraggingInfo) -> TransferKind? {
        let allowed = info.draggingSourceOperationMask
        if NSEvent.modifierFlags.contains(.command) && !NSEvent.modifierFlags.contains(.option) && allowed.contains(.move) { return .move }
        if allowed.contains(.copy) { return .copy }
        return nil
    }
    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard dropDestination(row: row, operation: operation) != nil, let kind = dropKind(info),
              !FilePasteboard.readLocations(from: info.draggingPasteboard).isEmpty else { return [] }
        return kind == .copy ? .copy : .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let destination = dropDestination(row: row, operation: dropOperation), let kind = dropKind(info) else { return false }
        let sources = FilePasteboard.readLocations(from: info.draggingPasteboard)
        guard !sources.isEmpty else { return false }
        owner.onDrop(.init(kind: kind, sources: sources, destinationDirectory: destination)); return true
    }
    @objc func activate() {
        guard let table, entries.indices.contains(table.clickedRow) else { return }
        owner.onActivate(entries[table.clickedRow])
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.items.filter { $0.tag == 884 }.forEach { menu.removeItem($0) }
        let entries = owner.tab.selectedEntries
        guard let first = entries.first else { return }
        let item = NSMenuItem(title: "Open With", action: nil, keyEquivalent: ""); item.tag = 884
        let submenu = NSMenu()
        for app in SystemFileActions.applications(for: first.location) {
            let option = NSMenuItem(title: app.deletingPathExtension().lastPathComponent, action: #selector(openWith(_:)), keyEquivalent: "")
            option.target = self; option.representedObject = app; submenu.addItem(option)
        }
        item.submenu = submenu; menu.addItem(item)
        for item in menu.items where (item.representedObject as? CommandBox)?.command == .showPackage { item.isHidden = first.kind != .package }
    }
    @objc private func openWith(_ sender: NSMenuItem) {
        guard let application = sender.representedObject as? URL else { return }
        let locations = owner.tab.selectedEntries.map(\.location)
        SystemFileActions.open(locations, with: application) { [weak self] message in
            self?.table?.window?.presentError(FileOperationError.message(message))
        }
    }
    @objc func contextAction(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? CommandBox else { return }
        owner.onCommand(box.command)
    }
}
