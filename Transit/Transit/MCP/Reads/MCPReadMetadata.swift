#if os(macOS)
import Foundation

nonisolated enum MCPReadPolicy: String, Codable, Sendable {
    case cached
    case refreshIfNeeded = "refresh_if_needed"
}

nonisolated enum ReadSyncState: String, Codable, Sendable {
    case active, inactive
}

nonisolated enum ReadFreshnessAssessment: String, Codable, Sendable {
    case recentImport = "recent_import"
    case stale, unknown
    case notApplicable = "not_applicable"
}

nonisolated enum ReadImportEvidence: String, Codable, Sendable {
    case completedImport = "completed_import"
    case none
}

nonisolated enum ReadRefreshOutcome: String, Codable, Sendable {
    case notRequested = "not_requested"
    case recentImport = "recent_import"
    case importObserved = "import_observed"
    case failed, timeout, unavailable
}

/// Timestamp strings are frozen UTC ISO 8601 milliseconds from the capture producer.
nonisolated struct ReadFreshness: Encodable, Sendable {
    let syncState: ReadSyncState
    let assessment: ReadFreshnessAssessment
    let assessedAt: String
    let lastImportedAt: String?
    let evidence: ReadImportEvidence
    let recentImportThresholdMs: Int

    private enum CodingKeys: String, CodingKey {
        case syncState, assessment, assessedAt, lastImportedAt, evidence, recentImportThresholdMs
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(syncState, forKey: .syncState)
        try container.encode(assessment, forKey: .assessment)
        try container.encode(assessedAt, forKey: .assessedAt)
        // The wire contract requires an explicit nullable import timestamp.
        try container.encode(lastImportedAt, forKey: .lastImportedAt)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(recentImportThresholdMs, forKey: .recentImportThresholdMs)
    }
}

nonisolated struct ReadExecutionMetadata: Encodable, Sendable {
    let policy: MCPReadPolicy
    let refreshOutcome: ReadRefreshOutcome
    let budgetMs: Int
}

nonisolated struct ReadCaptureMetadata: Encodable, Sendable {
    let asOf: String
    let snapshotId: String
    let freshness: ReadFreshness
    let read: ReadExecutionMetadata
}

nonisolated enum ReadFailureCategory: String, Encodable, Sendable {
    case storageFailure = "storage_failure"
    case serializationFailure = "serialization_failure"
    case incoherentCapture = "incoherent_capture"
    case timeout = "READ_TIMEOUT"
    case busy = "READ_BUSY"
}

/// A failed request has no invented capture identity or capture timestamp.
nonisolated struct ReadFailureMetadata: Encodable, Sendable {
    let requestId: String
    let category: ReadFailureCategory
    let read: ReadExecutionMetadata
}

nonisolated enum MCPReadResultMetadata: Encodable, Sendable {
    case capture(ReadCaptureMetadata)
    case failure(ReadFailureMetadata)

    func encode(to encoder: Encoder) throws {
        switch self {
        case .capture(let metadata): try metadata.encode(to: encoder)
        case .failure(let metadata): try metadata.encode(to: encoder)
        }
    }
}

nonisolated struct MCPToolResultMetadata: Encodable, Sendable {
    let read: MCPReadResultMetadata

    private enum CodingKeys: String, CodingKey {
        case read = "me.nore.ig.transit/read"
    }
}
#endif
