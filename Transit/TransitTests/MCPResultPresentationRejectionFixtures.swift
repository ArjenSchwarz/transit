#if os(macOS)
@testable import Transit
nonisolated struct MCPPresentationRejectionFixture: Sendable {
    let code: String
    let accepted: Bool

    static let all: [MCPPresentationRejectionFixture] = [
        .init(code: "INTERRUPTED_BEFORE_COMMIT", accepted: true),
        .init(code: "INTERNAL_ERROR", accepted: true),
        .init(code: "INTERNAL_ERROR", accepted: false)
    ]
}

nonisolated struct MCPPresentationCodeFixture: Sendable {
    let code: String
    let category: MCPResultErrorCategory

    static let all: [MCPPresentationCodeFixture] = [
        .init(code: "INVALID_INPUT", category: .invalidInput),
        .init(code: "TASK_NOT_FOUND", category: .notFound),
        .init(code: "AMBIGUOUS_TASK_ID", category: .ambiguousIdentity),
        .init(code: "REVISION_CONFLICT", category: .revisionConflict),
        .init(code: "IDEMPOTENCY_KEY_REUSED", category: .keyConflict),
        .init(code: "PERSISTENCE_UNAVAILABLE", category: .storageFailure),
        .init(code: "READ_BUSY", category: .admissionBusy),
        .init(code: "READ_TIMEOUT", category: .deadlineExceeded),
        .init(code: "QUERY_CAPACITY_EXCEEDED", category: .retentionCapacity),
        .init(code: "INVALID_CURSOR", category: .invalidCursor),
        .init(code: "INVALID_SNAPSHOT", category: .invalidCursor),
        .init(code: "SNAPSHOT_INCOMPATIBLE", category: .invalidInput),
        .init(code: "IDENTITY_AMBIGUITY", category: .ambiguousIdentity),
        .init(code: "QUERY_EXPIRED", category: .expiredCursor),
        .init(code: "OUTCOME_UNCERTAIN", category: .outcomeUncertain)
    ]
}
#endif
