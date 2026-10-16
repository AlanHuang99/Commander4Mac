import SwiftUI
import AppKit
import Quartz
import CommanderCore

struct FileGridView: NSViewRepresentable {
    var browser: FileTableView
    func makeCoordinator() -> GridCoordinator { GridCoordinator(owner: browser) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        let grid = CommanderCollectionView()
        grid.isSelectable = true; grid.allowsMultipleSelection = true
        grid.backgroundColors = [.textBackgroundColor]
        let layout = NSCollectionViewFlowLayout(); layout.minimumInteritemSpacing = 8; layout.minimumLineSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        grid.collectionViewLayout = layout
        grid.register(GridItem.self, forItemWithIdentifier: .init("file"))
        grid.dataSource = context.coordinator; grid.delegate = context.coordinator
        grid.registerForDraggedTypes([.fileURL]); grid.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        grid.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        grid.setAccessibilityIdentifier(browser.paneID.rawValue + ".fileGrid")
        grid.setAccessibilityLabel(browser.paneID == .left ? "Left file icons" : "Right file icons")
        grid.onCommand = browser.onCommand; grid.onFocus = browser.onFocus
        grid.onActivate = { [weak coordinator = context.coordinator] index in
            guard let coordinator, coordinator.entries.indices.contains(index) else { return }
            coordinator.owner.onActivate(coordinator.entries[index])
        }
        let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = context.coordinator
        for (title, command) in [("Open", TableCommand.open), ("Quick Look", .preview), ("Rename", .rename), ("Copy Path", .copyPath), ("Add to Shelf", .stage), ("Copy to Other Pane", .copy), ("Move to Other Pane", .move), ("Move to Trash", .trash), ("Show Package Contents", .showPackage)] {
            let item = NSMenuItem(title: title, action: #selector(GridCoordinator.contextAction(_:)), keyEquivalent: "")
            item.target = context.coordinator; item.representedObject = CommandBox(command); menu.addItem(item)
        }
        grid.menu = menu
        let doubleClick = NSClickGestureRecognizer(target: context.coordinator, action: #selector(GridCoordinator.doubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2; doubleClick.delaysPrimaryMouseButtonEvents = false
        grid.addGestureRecognizer(doubleClick)
        grid.frame = scroll.contentView.bounds; grid.autoresizingMask = [.width]
        scroll.documentView = grid; context.coordinator.grid = grid
        context.coordinator.observe(scroll)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator; coordinator.owner = browser
        guard let grid = coordinator.grid else { return }
        grid.onFocus = browser.onFocus; grid.onCommand = browser.onCommand; grid.previewController = browser.previewController
        let tab = browser.tab
        let changedTab = coordinator.tabID != tab.id
        if changedTab { coordinator.needsRestore = true }
        coordinator.synchronizing = true
        if coordinator.entriesRevision != tab.entriesRevision || changedTab || coordinator.options != tab.options {
            coordinator.entries = tab.visibleEntries
            coordinator.entriesRevision = tab.entriesRevision
            coordinator.indexByID = Dictionary(uniqueKeysWithValues: coordinator.entries.enumerated().map { ($0.element.id, $0.offset) })
            coordinator.tabID = tab.id; coordinator.options = tab.options
            if let layout = grid.collectionViewLayout as? NSCollectionViewFlowLayout {
                layout.itemSize = NSSize(width: max(110, tab.options.gridIconSize + 36), height: tab.options.gridIconSize + tab.options.textSize * 2.6 + 18)
            }
            grid.reloadData()
        }
        let selection = Set(tab.selection.compactMap { coordinator.indexByID[$0] }.map { IndexPath(item: $0, section: 0) })
        if grid.selectionIndexPaths != selection { grid.selectionIndexPaths = selection }
        if coordinator.needsRestore, !coordinator.entries.isEmpty {
            if let anchor = tab.scrollAnchor, let index = coordinator.entries.firstIndex(where: { $0.id == anchor }) {
                grid.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .top)
            }
            coordinator.needsRestore = false
        }
        grid.layoutSubtreeIfNeeded()
        RuntimeMetrics.rendered(tab, lastGeneration: &coordinator.renderedGeneration)
        coordinator.synchronizing = false
        if browser.isActive && (!coordinator.wasActive || (browser.focusRequest != nil && coordinator.lastFocusRequest != browser.focusRequest)) {
            grid.window?.makeFirstResponder(grid); coordinator.lastFocusRequest = browser.focusRequest
        }
        coordinator.wasActive = browser.isActive
        if browser.isActive, let request = browser.renameRequest, coordinator.lastRenameRequest != request {
            coordinator.lastRenameRequest = request; coordinator.beginRename()
        }
    }
}

@MainActor final class GridCoordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
    var owner: FileTableView
    weak var grid: CommanderCollectionView?
    var entries: [FileEntry] = []
    var entriesRevision: UInt64?
    var indexByID: [EntryID: Int] = [:]
    var tabID: UUID?
    var options = ViewOptions()
    var synchronizing = false
    var wasActive = false
    var renderedGeneration: UInt64?
    var needsRestore = true
    var lastFocusRequest: UUID?
    var lastRenameRequest: UUID?
    private var editingEntry: FileEntry?
    private var observer: NotificationToken?
    init(owner: FileTableView) { self.owner = owner }
    func observe(_ scroll: NSScrollView) {
        scroll.contentView.postsBoundsChangedNotifications = true
        observer = NotificationToken(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.synchronizing, let index = self.grid?.indexPathsForVisibleItems().map(\.item).min(), self.entries.indices.contains(index) else { return }
                self.owner.tab.scrollAnchor = self.entries[index].id
            }
        })
    }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { entries.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .init("file"), for: indexPath) as! GridItem
        item.configure(entries[indexPath.item], options: options); return item
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { syncSelection() }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { syncSelection() }
    private func syncSelection() {
        guard !synchronizing, let grid else { return }
        owner.tab.selection = Set(grid.selectionIndexPaths.compactMap { entries.indices.contains($0.item) ? entries[$0.item].id : nil })
    }
    @objc func doubleClick(_ sender: NSClickGestureRecognizer) {
        guard let grid, let path = grid.indexPathForItem(at: sender.location(in: grid)), entries.indices.contains(path.item) else { return }
        owner.onActivate(entries[path.item])
    }
    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items {
            if let command = (item.representedObject as? CommandBox)?.command { item.isEnabled = command.isSupported(in: owner) }
        }
    }
    @objc func contextAction(_ sender: NSMenuItem) { if let box = sender.representedObject as? CommandBox { owner.onCommand(box.command) } }
    func beginRename() {
        guard let grid, grid.selectionIndexPaths.count == 1, let path = grid.selectionIndexPaths.first,
              let item = grid.item(at: path) as? GridItem, let field = item.textField else { return }
        editingEntry = entries[path.item]; field.isEditable = true; field.isSelectable = true; field.delegate = self
        grid.window?.makeFirstResponder(field); field.selectText(nil)
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let entry = editingEntry else { return }
        let canceled = (notification.userInfo?["NSTextMovement"] as? Int) == NSTextMovement.cancel.rawValue
        let name = field.stringValue
        editingEntry = nil; field.isEditable = false; field.isSelectable = false; field.delegate = nil; field.stringValue = entry.name
        if !canceled && name != entry.name { owner.onRename(entry, name) }
    }
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? { entries[indexPath.item].location.isLocal ? entries[indexPath.item].location.url as NSURL : nil }
    private func target(_ index: Int, operation: NSCollectionView.DropOperation) -> FileLocation? {
        if operation == .on && entries.indices.contains(index) { return entries[index].isDirectory ? entries[index].location : nil }
        return owner.tab.location
    }
    private func kind(_ info: any NSDraggingInfo) -> TransferKind? {
        if NSEvent.modifierFlags.contains(.command) && !NSEvent.modifierFlags.contains(.option) && info.draggingSourceOperationMask.contains(.move) { return .move }
        return info.draggingSourceOperationMask.contains(.copy) ? .copy : nil
    }
    func collectionView(_ collectionView: NSCollectionView, validateDrop info: any NSDraggingInfo, proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        guard target(proposedIndexPath.pointee.item, operation: dropOperation.pointee) != nil,
              let kind = kind(info), !FilePasteboard.readLocations(from: info.draggingPasteboard).isEmpty else { return [] }
        return kind == .copy ? .copy : .move
    }
    func collectionView(_ collectionView: NSCollectionView, acceptDrop info: any NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        guard let destination = target(indexPath.item, operation: dropOperation), let kind = kind(info) else { return false }
        let sources = FilePasteboard.readLocations(from: info.draggingPasteboard)
        guard !sources.isEmpty else { return false }
        owner.onDrop(.init(kind: kind, sources: sources, destinationDirectory: destination)); return true
    }
}

@MainActor final class GridItem: NSCollectionViewItem {
    private var iconSize: [NSLayoutConstraint] = []
    override func loadView() {
        view = NSView(); view.wantsLayer = true; view.layer?.cornerRadius = 6
        let image = NSImageView(); image.translatesAutoresizingMaskIntoConstraints = false; image.imageScaling = .scaleProportionallyUpOrDown
        let text = NSTextField(wrappingLabelWithString: ""); text.translatesAutoresizingMaskIntoConstraints = false
        text.maximumNumberOfLines = 2; text.lineBreakMode = .byTruncatingMiddle; text.alignment = .center
        view.addSubview(image); view.addSubview(text); imageView = image; textField = text
        iconSize = [image.widthAnchor.constraint(equalToConstant: 64), image.heightAnchor.constraint(equalToConstant: 64)]
        NSLayoutConstraint.activate(iconSize + [image.topAnchor.constraint(equalTo: view.topAnchor, constant: 8), image.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            text.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 6), text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            text.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4), text.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -5)])
    }
    override var isSelected: Bool { didSet { view.layer?.backgroundColor = (isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.25) : .clear).cgColor } }
    func configure(_ entry: FileEntry, options: ViewOptions) {
        _ = view
        imageView?.image = FileIconCache.shared.icon(for: entry)
        iconSize.forEach { $0.constant = options.gridIconSize }
        textField?.font = .systemFont(ofSize: options.textSize); textField?.stringValue = entry.name
        textField?.setAccessibilityLabel(entry.name); view.toolTip = entry.location.url.path
    }
}

@MainActor final class CommanderCollectionView: NSCollectionView {
    var onCommand: ((TableCommand) -> Void)?
    var onFocus: (() -> Void)?
    var onActivate: ((Int) -> Void)?
    weak var previewController: QuickLookController?
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { previewController?.hasItems == true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = previewController; panel.delegate = previewController }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil; panel.delegate = nil }
    @objc func copy(_ sender: Any?) { onCommand?(.copyClipboard) }
    @objc func paste(_ sender: Any?) { onCommand?(.pasteClipboard) }
    override func becomeFirstResponder() -> Bool { let accepted = super.becomeFirstResponder(); if accepted { onFocus?() }; return accepted }
    override func rightMouseDown(with event: NSEvent) {
        onFocus?()
        if let path = indexPathForItem(at: convert(event.locationInWindow, from: nil)), !selectionIndexPaths.contains(path) { selectionIndexPaths = [path] }
        super.rightMouseDown(with: event)
    }
    override func keyDown(with event: NSEvent) {
        RuntimeMetrics.record("keyDelivery", since: event.timestamp)
        if let command = FileTableCommandHandler.command(for: event) { onCommand?(command) }
        else { super.keyDown(with: event) }
    }
}
