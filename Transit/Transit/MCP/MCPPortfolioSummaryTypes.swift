#if os(macOS)
import Foundation

/// Service failures remain distinct from parser validation and diagnosed relationship corruption.
nonisolated enum PortfolioSummaryError: Error, Equatable {
    case identityAmbiguity
    case incoherentCapture
}

nonisolated enum CompletionWindowError: Error, Equatable {
    case invalidInput
}

/// Parsed instants. Strict wire parsing and UTC formatting are supplied by the window parser.
nonisolated struct CompletionWindow: Sendable, Equatable {
    let start: Date
    let end: Date
}

/// Stored independently of app model enums so value-only work can leave MainActor.
/// Values are populated by aggregation, not computed independently from live records.
nonisolated struct PortfolioStatusCounts: Sendable, Equatable {
    let idea: Int
    let planning: Int
    let spec: Int
    let readyForImplementation: Int
    let inProgress: Int
    let readyForReview: Int
    let done: Int
    let abandoned: Int
}

nonisolated struct PortfolioRecentCompletions: Sendable, Equatable {
    let done: Int
    let abandoned: Int
    let missingCompletionDateCount: Int
}

/// Also represents the unassigned, invalid-association and unresolved-project partitions.
nonisolated struct PortfolioTaskBreakdown: Sendable, Equatable {
    let countsByStatus: PortfolioStatusCounts
    let totalTaskCount: Int
    let recentCompletions: PortfolioRecentCompletions
}

nonisolated enum PortfolioActivityKind: String, Sendable {
    case taskCreation = "task_creation"
    case taskStatus = "task_status"
    case commentCreation = "comment_creation"
    case milestoneCreation = "milestone_creation"
    case milestoneStatus = "milestone_status"
}

nonisolated struct PortfolioActivityEvidence: Sendable, Equatable {
    let timestamp: Date
    let kind: PortfolioActivityKind
    let id: UUID
}

/// A discriminator is capture-local diagnostic evidence, never a new persistent identity.
nonisolated struct PortfolioIdentitySample: Sendable, Equatable {
    let entityKind: String
    let id: UUID
    let displayId: Int?
    let discriminator: String?
}

nonisolated struct PortfolioDiagnostic: Sendable, Equatable {
    let category: String
    let affectedCount: Int
    let samples: [PortfolioIdentitySample]
    let sampleComplete: Bool
}

nonisolated struct PortfolioMilestoneSummary: Sendable, Equatable {
    let milestoneId: UUID
    let displayId: Int?
    let name: String
    let rawStatus: String
    let status: String
    let invalidStatus: Bool
    let countsByStatus: PortfolioStatusCounts
    let totalTaskCount: Int
    let recentCompletions: PortfolioRecentCompletions
}

nonisolated struct PortfolioProjectSummary: Sendable, Equatable {
    let projectId: UUID
    let name: String
    let countsByStatus: PortfolioStatusCounts
    let totalTaskCount: Int
    let ideaCount: Int
    let inProgressCount: Int
    let workflowTaskCount: Int
    let nonterminalTaskCount: Int
    let recentCompletions: PortfolioRecentCompletions
    let lastRecordedActivity: PortfolioActivityEvidence?
    let milestones: [PortfolioMilestoneSummary]
    let unassignedMilestone: PortfolioTaskBreakdown
    let invalidMilestoneAssociations: PortfolioTaskBreakdown
    let diagnostics: [PortfolioDiagnostic]
}

/// Pure aggregation output. Shared read metadata and pagination belong to the enclosing result.
nonisolated struct PortfolioSummary: Sendable, Equatable {
    let projects: [PortfolioProjectSummary]
    let unresolvedProjects: PortfolioTaskBreakdown
    let diagnostics: [PortfolioDiagnostic]
    let completionWindow: CompletionWindow
}

nonisolated enum SnapshotTaskDetail: String, Sendable {
    case summary
    case full
}

/// Encoded from an immutable shared ReadTask; no live model is retained by projection.
nonisolated struct EncodedTaskRecord: Sendable, Equatable {
    let json: Data
}
#endif
