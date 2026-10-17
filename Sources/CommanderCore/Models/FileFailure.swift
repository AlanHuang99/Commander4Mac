// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation

public struct FileFailure: Error, LocalizedError, Sendable {
    public enum Category: String, Sendable { case accessDenied, notFound, conflict, canceled, other }
    public let category: Category
    public let domain: String
    public let code: Int
    public let location: FileLocation
    public let detail: String
    public var errorDescription: String? { detail }
    public init(_ error: Error, at location: FileLocation) {
        let ns = error as NSError
        domain = ns.domain; code = ns.code; self.location = location
        let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError
        let posix = ns.domain == NSPOSIXErrorDomain ? ns.code : (underlying?.domain == NSPOSIXErrorDomain ? underlying?.code : nil)
        if posix == Int(EACCES) || posix == Int(EPERM) || (ns.domain == NSCocoaErrorDomain && [257,513].contains(ns.code)) {
            category = .accessDenied
            detail = "Access denied to \(location.url.path). Check Full Disk Access and the item's permissions."
        } else if posix == Int(ENOENT) || (ns.domain == NSCocoaErrorDomain && [4,260].contains(ns.code)) {
            category = .notFound; detail = "This location is unavailable: \(location.url.path)"
        } else if posix == Int(EEXIST) || (ns.domain == NSCocoaErrorDomain && ns.code == 516) {
            category = .conflict; detail = "An item already exists at \(location.url.path)."
        } else {
            category = .other; detail = ns.localizedDescription
        }
    }
}
