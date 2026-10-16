import Foundation
import Darwin

public struct LocalTransferPlanner: Sendable {
    public init() {}
    public func plan(_ request: TransferRequest) throws -> TransferPlan {
        try request.destinationDirectory.requireLocal()
        for source in request.sources { try source.requireLocal() }
        guard !request.sources.isEmpty else { throw FileOperationError.message("Select files to transfer.") }
        let destination = request.destinationDirectory.url
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &directory), directory.boolValue else {
            throw FileOperationError.message("The destination folder is unavailable.")
        }
        let destinationIdentity = try LocationResolver.identity(at: destination.resolvingSymlinksInPath())
        let canonicalDestination = destination.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        var seen: Set<FileLocation> = []
        var items: [PlannedTransfer] = []
        for source in request.sources where seen.insert(source).inserted {
            let version = try ItemVersion.read(at: source.url)
            let target = destination.appendingPathComponent(source.url.lastPathComponent)
            if let existing = try? ItemVersion.read(at: target), existing.identity == version.identity {
                throw FileOperationError.message("Source and destination refer to the same item: \(source.title)")
            }
            if version.isDirectory {
                let sourceComponents = source.url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
                if canonicalDestination.starts(with: sourceComponents) {
                    throw FileOperationError.message("A folder cannot be transferred into itself or one of its descendants.")
                }
            }
            items.append(.init(id: UUID(), source: source, destination: target, sourceVersion: version))
        }
        for item in items where item.isDirectory {
            let parent = item.source.url.resolvingSymlinksInPath().pathComponents
            for other in items where other.id != item.id {
                if other.source.url.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents.starts(with: parent) {
                    throw FileOperationError.message("The selection includes a folder and an item already inside it. Remove the overlapping item and retry.")
                }
            }
        }
        return .init(request: request, items: items, destinationIdentity: destinationIdentity)
    }
}
