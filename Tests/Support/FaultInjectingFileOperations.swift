// Commander4Mac original code: GPL-3.0-only with the Citadel linking permission.
// See LICENSE and LICENSE-EXCEPTION at the repository root.

import Foundation
import CommanderCore

final class FaultInjectingFileOperations: FileOperationBackend, @unchecked Sendable {
    private let system = SystemFileOperationBackend()
    private let lock = NSLock()
    private var raceDestination: URL?
    private let simulateCrossVolume: Bool
    private let failRemoval: Bool
    init(raceDestination: URL? = nil, simulateCrossVolume: Bool = false, failRemoval: Bool = false) {
        self.raceDestination = raceDestination; self.simulateCrossVolume = simulateCrossVolume; self.failRemoval = failRemoval
    }
    func version(at url: URL) throws -> ItemVersion { try system.version(at: url) }
    func supportsAtomicMove(from source: URL, to destination: URL) -> Bool { !simulateCrossVolume && system.supportsAtomicMove(from: source, to: destination) }
    func renameExclusive(from source: URL, to destination: URL) throws {
        lock.lock(); let race = raceDestination; raceDestination = nil; lock.unlock()
        if let race { try Data("racing writer".utf8).write(to: race) }
        try system.renameExclusive(from: source, to: destination)
    }
    func swap(_ first: URL, _ second: URL) throws { try system.swap(first, second) }
    func removeSource(at url: URL, expecting version: ItemVersion) throws {
        if failRemoval { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)) }
        try system.removeSource(at: url, expecting: version)
    }
}
