import Foundation
import Darwin

public struct WebDAVEndpoint: Sendable {
    public let profile: ConnectionProfile
    public init(profile: ConnectionProfile) throws {
        self.profile = try profile.validated()
        guard profile.protocolKind == .webdav else { throw Self.invalid() }
        _ = try url(try RemotePath("/"))
    }
    public func url(_ path: RemotePath, collection: Bool = false) throws -> URL {
        try RemotePathRules.validate(path, for: .webdav)
        var parts = URLComponents(); parts.scheme = profile.secure ? "https" : "http"
        parts.host = profile.host; parts.port = profile.port
        let base = profile.basePath == "/" ? "" : profile.basePath
        parts.path = base + (path.rawValue == "/" ? "/" : path.rawValue) + (collection && path.rawValue != "/" ? "/" : "")
        guard let url = parts.url, parts.user == nil, parts.password == nil else { throw Self.invalid() }
        return url
    }
    public func remotePath(href: String) throws -> RemotePath {
        guard let c = URLComponents(string: href), c.query == nil, c.fragment == nil, c.user == nil, c.password == nil else { throw Self.invalid() }
        if c.scheme != nil || c.host != nil {
            guard c.scheme?.lowercased() == (profile.secure ? "https" : "http"), c.host?.lowercased() == profile.host.lowercased(), (c.port ?? (profile.secure ? 443 : 80)) == profile.port else { throw Self.invalid() }
        }
        guard c.percentEncodedPath.hasPrefix("/") else { throw Self.invalid() }
        let encodedPath = c.percentEncodedPath
        guard !encodedPath.contains("//") else { throw Self.invalid() }
        let segments = try encodedPath.split(separator: "/", omittingEmptySubsequences: true).map { segment -> String in
            guard let value = String(segment).removingPercentEncoding, !value.isEmpty, value != ".", value != "..", !value.contains("/"), !value.contains("\\"), !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw Self.invalid() }
            return value
        }
        let base = profile.basePath.split(separator: "/").map(String.init)
        guard segments.count >= base.count, zip(segments, base).allSatisfy({ Data($0.0.utf8) == Data($0.1.utf8) }) else { throw Self.invalid() }
        return try RemotePath("/" + segments.dropFirst(base.count).joined(separator: "/"))
    }
    static func invalid() -> FileOperationError { .message("The WebDAV server supplied an invalid or out-of-scope resource path.") }
}

public struct WebDAVListing: Sendable {
    public let entries: [FileEntry]
    public let metadata: RemoteFileMetadata?
    public static func parse(_ data: Data, endpoint: WebDAVEndpoint, location: FileLocation, depth: Int) throws -> Self {
        guard data.count <= 8_388_608, let xml = String(data: data, encoding: .utf8), !xml.uppercased().contains("<!DOCTYPE"), !xml.uppercased().contains("<!ENTITY"), let requested = location.remotePath, location.profileID == endpoint.profile.id, location.connectionProtocol == .webdav, depth == 0 || depth == 1 else { throw invalid() }
        let delegate = DAVXMLDelegate(); let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse(), !delegate.invalid, let root = delegate.root, root.isDAV("multistatus") else { throw invalid() }
        var entries: [FileEntry] = []; var own: RemoteFileMetadata?; var seen = Set<RemotePath>()
        for node in root.children {
            guard node.isDAV("response"), let href = node.child("href")?.text.trimmingCharacters(in: .whitespacesAndNewlines) else { throw invalid() }
            let path = try endpoint.remotePath(href: href)
            guard seen.insert(path).inserted, path == requested || (depth == 1 && path.parent == requested && path != requested) else { throw invalid() }
            if let status = node.child("status"), statusCode(status.text) != 200 { throw invalid() }
            var props: [String: DAVXMLNode] = [:]
            for block in node.children.filter({ $0.isDAV("propstat") }) {
                guard let status = block.child("status"), let prop = block.child("prop") else { throw invalid() }
                if statusCode(status.text) == 200 {
                    for value in prop.children where value.namespace == "DAV:" {
                        guard props[value.name] == nil else { throw invalid() }; props[value.name] = value
                    }
                }
            }
            guard let type = props["resourcetype"] else { throw invalid() }
            let directory = type.children.contains(where: { $0.isDAV("collection") })
            guard type.children.allSatisfy({ $0.isDAV("collection") }) else { throw invalid() }
            let size: UInt64?
            if let raw = props["getcontentlength"]?.text.trimmingCharacters(in: .whitespacesAndNewlines) {
                guard let number = UInt64(raw), number <= UInt64(Int64.max) else { throw invalid() }; size = number
            } else { size = nil }
            let tag = props["getetag"]?.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let strongTag = tag.flatMap { value -> String? in
                guard value.hasPrefix("\""), value.hasSuffix("\""), value.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }), !value.dropFirst().dropLast().contains("\"") else { return nil }; return value
            }
            let modified = props["getlastmodified"].flatMap { httpDate($0.text) }
            let metadata = RemoteFileMetadata(size: directory ? nil : size, permissions: UInt32(directory ? S_IFDIR : S_IFREG), modified: modified, revision: strongTag)
            if path == requested { own = metadata }
            else { entries.append(.init(location: .webdav(profileID: endpoint.profile.id, path: path), name: String(path.rawValue.split(separator: "/").last!), kind: directory ? .directory : .file, byteSize: size.map(Int64.init), modificationDate: modified)) }
        }
        return .init(entries: entries, metadata: own)
    }
    private static func statusCode(_ value: String) -> Int? { let parts = value.split(separator: " "); guard parts.count >= 2, parts[0].hasPrefix("HTTP/") else { return nil }; return Int(parts[1]) }
    private static func httpDate(_ value: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    private static func invalid() -> FileOperationError { .message("The WebDAV server returned an incomplete, unsafe, or oversized directory response.") }
}
private final class DAVXMLNode {
    let name: String; let namespace: String; var text = ""; var children: [DAVXMLNode] = []
    init(_ name: String, _ namespace: String) { self.name = name; self.namespace = namespace }
    func isDAV(_ value: String) -> Bool { namespace == "DAV:" && name == value }
    func child(_ value: String) -> DAVXMLNode? { children.first { $0.isDAV(value) } }
}
private final class DAVXMLDelegate: NSObject, XMLParserDelegate {
    var root: DAVXMLNode?; var stack: [DAVXMLNode] = []; var invalid = false; var count = 0
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        count += 1
        guard stack.count < 32, count <= 500_000 else { invalid = true; parser.abortParsing(); return }
        let node = DAVXMLNode(name, namespaceURI ?? "")
        if let parent = stack.last { parent.children.append(node) } else if root == nil { root = node } else { invalid = true; parser.abortParsing() }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters value: String) { stack.last?.text += value }
    func parser(_ parser: XMLParser, didEndElement: String, namespaceURI: String?, qualifiedName: String?) { if !stack.isEmpty { stack.removeLast() } }
    func parser(_ parser: XMLParser, resolveExternalEntityName: String, systemID: String?) -> Data? { invalid = true; parser.abortParsing(); return nil }
}
