import Foundation

public enum JobState: String, Codable, Sendable {
    case queued, planning, running, awaitingConflict, cancelRequested, completed, failed, canceled
    public var isTerminal: Bool { [.completed, .failed, .canceled].contains(self) }
}
public enum ItemOutcomeState: String, Codable, Sendable { case completed, skipped, failed, partial, canceled }
public struct ItemOperationOutcome: Identifiable, Codable, Sendable {
    public let id: UUID
    public let source: FileLocation
    public let destination: FileLocation?
    public let state: ItemOutcomeState
    public let detail: String?
    public init(id: UUID = UUID(), source: FileLocation, destination: FileLocation? = nil, state: ItemOutcomeState, detail: String? = nil) {
        self.id = id; self.source = source; self.destination = destination; self.state = state; self.detail = detail
    }
}
public struct OperationResult: Codable, Sendable {
    public let jobID: UUID
    public let outcomes: [ItemOperationOutcome]
    public let state: JobState
    public init(jobID: UUID, outcomes: [ItemOperationOutcome], state: JobState) { self.jobID = jobID; self.outcomes = outcomes; self.state = state }
}
public struct CopyProgress: Sendable {
    public var bytesCopied: Int64
    public var completedItems: Int
    public init(bytesCopied: Int64 = 0, completedItems: Int = 0) { self.bytesCopied = bytesCopied; self.completedItems = completedItems }
}
public enum OperationEvent: Sendable { case state(JobState), progress(CopyProgress), item(ItemOperationOutcome) }
public struct JobSnapshot: Identifiable, Sendable {
    public var id: UUID { request.id }
    public let request: TransferRequest
    public var state: JobState = .queued
    public var progress = CopyProgress()
    public var outcomes: [ItemOperationOutcome] = []
    public var pendingConflict: TransferConflict?
    public init(request: TransferRequest) { self.request = request }
}
