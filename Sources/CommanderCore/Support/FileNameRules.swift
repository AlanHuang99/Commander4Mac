import Foundation

public enum FileNameRules {
    public static func validateComponent(_ name: String) throws -> String {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw FileOperationError.message("Enter a single file or folder name without path separators.")
        }
        return name
    }
    public static func keepBothCandidate(originalName: String, ordinal: Int) -> String {
        let suffix = ordinal <= 1 ? " copy" : " copy \(ordinal)"
        let ns = originalName as NSString
        let ext = ns.pathExtension
        if ext.isEmpty || (originalName.hasPrefix(".") && !originalName.dropFirst().contains(".")) { return originalName + suffix }
        return ns.deletingPathExtension + suffix + "." + ext
    }
}
