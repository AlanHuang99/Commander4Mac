import Foundation

public enum FileDropRequest {
    public static func locations(from urlStrings: [String]) -> [FileLocation] {
        var seen: Set<FileLocation> = []
        return urlStrings.compactMap { value in
            guard let url = URL(string: value), url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else { return nil }
            let location = FileLocation.local(url)
            return seen.insert(location).inserted ? location : nil
        }
    }
    public static func transfer(urlStrings: [String], kind: TransferKind, destination: FileLocation) -> TransferRequest? {
        let sources = locations(from: urlStrings)
        return sources.isEmpty ? nil : .init(kind: kind, sources: sources, destinationDirectory: destination)
    }
}
