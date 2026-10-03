#if os(macOS)
import Foundation

/// Canonical encoded PersistentIdentifier; domain UUIDs are not physical identity.
nonisolated struct LocalRecordKey: Hashable, Sendable {
    let encodedIdentifier: Data
}

nonisolated enum ReadCaptureScope: Equatable, Sendable {
    case wholePortfolio
    /// Canonical unique physical project keys. Identity closure cannot expand this scope.
    case projects([LocalRecordKey])
    case selectedQuery
}

nonisolated enum CaptureCompleteness: Sendable {
    case selectedRead
    /// Complete declared scope plus required identity/comment closure.
    case completePortfolio
}

nonisolated struct CapturedReadView: Sendable {
    let completeness: CaptureCompleteness
    let captureScope: ReadCaptureScope
    let metadata: ReadCaptureMetadata
    let createdAt: ContinuousClock.Instant
    let retentionDeadline: ContinuousClock.Instant
    let projects: [ReadProject]
    let tasks: [ReadTask]
    let milestones: [ReadMilestone]
    let comments: [ReadCommentEvidence]
}

nonisolated struct ReadProject: Sendable {
    let physicalKey: LocalRecordKey
    let id: UUID
    let name: String
    let projectDescription: String
    let gitRepo: String?
    let colorHex: String
    let taskKeys: [LocalRecordKey]
    let milestoneKeys: [LocalRecordKey]
    let selectedRecordJSON: Data
}

nonisolated struct ReadTask: Sendable {
    let physicalKey: LocalRecordKey
    let id: UUID
    let permanentDisplayId: Int?
    let name: String
    let taskDescription: String?
    let projectKey: LocalRecordKey?
    let milestoneKey: LocalRecordKey?
    let storedProjectID: UUID?
    let storedMilestoneID: UUID?
    let rawStatus: String
    let effectiveStatus: String
    let rawType: String
    let effectiveType: String
    let rawPriority: String
    let effectivePriority: String
    let metadata: [String: String]
    let metadataJSON: String?
    let creationDate: Date
    let lastStatusChangeDate: Date
    let completionDate: Date?
    let commentKeys: [LocalRecordKey]
    let selectedRecordJSON: Data
    /// Authoritative MCPRecordSnapshot.task r1, minted before removing comments.
    let revision: String?
    /// Mandatory alongside revision for selected tasks in completePortfolio; optional for identity closure.
    /// Selected portfolio tasks require complete commentKeys and canonical UUID comment evidence.
    let fullRecordWithoutCommentsJSON: Data?
    /// Output bodies only; may be nil when includeComments is false, even for a portfolio.
    let requestedCommentRecordsJSON: Data?
}

nonisolated struct ReadMilestone: Sendable {
    let physicalKey: LocalRecordKey
    let id: UUID
    let permanentDisplayId: Int?
    let name: String
    let milestoneDescription: String?
    let projectKey: LocalRecordKey?
    let storedProjectID: UUID?
    let rawStatus: String
    let effectiveStatus: String
    let creationDate: Date
    let lastStatusChangeDate: Date
    let completionDate: Date?
    let taskKeys: [LocalRecordKey]
    let selectedRecordJSON: Data
}

nonisolated struct ReadCommentEvidence: Sendable {
    let physicalKey: LocalRecordKey
    let id: UUID
    let taskKey: LocalRecordKey?
    let storedTaskID: UUID?
    let creationDate: Date
    let content: String
    let authorName: String
    let isAgent: Bool
    let selectedRecordJSON: Data
}

nonisolated protocol MCPRetainedViewSource: Sendable {
    func view(for snapshotID: String, now: ContinuousClock.Instant) throws -> CapturedReadView
}

/// Selectors are resolved by the builder inside its fence, never before capture.
nonisolated enum ReadProjectSelector: Sendable {
    case id(UUID)
    case name(String)
}

nonisolated enum ReadTaskCaptureDetail: Sendable {
    /// Preserve the ordinary summary path: no comment fetch unless requested.
    case summary
    /// Canonical revision covers all comments even when output comments are hidden.
    case fullRecord
}

nonisolated enum ReadCaptureSelection: Sendable {
    case projects
    case milestones
    case tasks(detail: ReadTaskCaptureDetail)
    /// Requires completePortfolio and full revision/comment identity evidence.
    case portfolio
}

nonisolated struct ReadCaptureRequest: Sendable {
    let projectSelectors: [ReadProjectSelector]?
    let selection: ReadCaptureSelection
    let completeness: CaptureCompleteness
    /// Output preference only; fullRecord/portfolio still capture canonical comment coverage.
    let includeComments: Bool
}

/// Local fence evidence only. This is not proof that a particular CloudKit import became visible.
nonisolated struct MCPReadCaptureBoundary: Sendable {
    let historyStoreIdentifier: String?
    let generation: UInt64
    let stablePersistentHistory: Bool
}

/// Synchronous actor entry: implementations must not suspend within the capture fence.
nonisolated protocol MCPReadCaptureSource: Sendable {
    @MainActor func capture(_ request: ReadCaptureRequest) throws -> CapturedReadView
}
#endif
