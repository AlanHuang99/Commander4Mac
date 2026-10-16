import AppKit
import CommanderCore
import UniformTypeIdentifiers

@MainActor
final class FileTableCoordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var owner: FileTableView
    weak var table: CommanderTableView?
    var entries: [FileEntry] = []
    var tabID: UUID?
    var options = ViewOptions()
    var synchronizing = false
    var wasActive = false
    private var icons: [String: NSImage] = [:]
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
            let iconKey = entry.kind == .directory ? "folder" : (entry.kind == .package ? "app" : entry.location.url.pathExtension)
            if icons[iconKey] == nil {
                if icons.count > 128 { icons.removeAll() }
                icons[iconKey] = NSWorkspace.shared.icon(for: entry.kind == .directory ? .folder : (entry.kind == .package ? .application : (UTType(filenameExtension: iconKey) ?? .item)))
            }
            cell.imageView?.image = icons[iconKey]
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
    @objc func activate() {
        guard let table, entries.indices.contains(table.clickedRow) else { return }
        owner.onActivate(entries[table.clickedRow])
    }
    @objc func contextAction(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? CommandBox else { return }
        owner.onCommand(box.command)
    }
}
