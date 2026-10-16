import AppKit
import UniformTypeIdentifiers
import CommanderCore

@MainActor final class FileIconCache {
    static let shared = FileIconCache()
    private var icons: [String: NSImage] = [:]
    func icon(for entry: FileEntry) -> NSImage {
        let key = entry.kind == .directory ? "folder" : (entry.kind == .package ? "application" : "ext:" + entry.location.url.pathExtension)
        if let image = icons[key] { return image }
        if icons.count >= 128 { icons.removeAll(keepingCapacity: true) }
        let type: UTType = entry.kind == .directory ? .folder : (entry.kind == .package ? .application : (UTType(filenameExtension: entry.location.url.pathExtension) ?? .item))
        let image = NSWorkspace.shared.icon(for: type); icons[key] = image; return image
    }
}
