import Foundation

/// Physical identity is independent of the imported domain UUID.
nonisolated struct TaskLinkTaskValue: Codable, Equatable, Sendable {
    let physicalKey: Data
    let id: UUID
    let name: String
    let status: String
}

nonisolated struct TaskLinkOccurrenceValue: Codable, Equatable, Sendable {
    let physicalKey: Data
    let id: UUID
    let kind: String
    let source: UUID
    let target: UUID
    let createdAt: Date
}

nonisolated struct TaskLinkRemovalValue: Codable, Equatable, Sendable {
    let physicalKey: Data
    let id: UUID
    let edgeId: UUID
    let kind: String
    let source: UUID
    let target: UUID
    let createdAt: Date
    let occurrenceRevision: String
    let removedAt: Date
}

nonisolated enum TaskLinkType: String, CaseIterable, Sendable {
    case blocks, blockedBy = "blocked-by", relatesTo = "relates-to"
    case introducedBy = "introduced-by", duplicateOf = "duplicate-of"

    func normalized(source: UUID, target: UUID) -> TaskLinkRelation {
        switch self {
        case .blocks: TaskLinkRelation(kind: "dependency", source: source, target: target)
        case .blockedBy: TaskLinkRelation(kind: "dependency", source: target, target: source)
        case .relatesTo:
            TaskLinkRelation(kind: "association",
                             source: source.uuidString < target.uuidString ? source : target,
                             target: source.uuidString < target.uuidString ? target : source)
        case .introducedBy: TaskLinkRelation(kind: "attribution", source: source, target: target)
        case .duplicateOf: TaskLinkRelation(kind: "duplicate", source: source, target: target)
        }
    }
}

nonisolated struct TaskLinkRelation: Codable, Hashable, Sendable {
    let kind: String
    let source: UUID
    let target: UUID
}

nonisolated enum TaskLinkBlockerAssessment: String, Sendable {
    case unblocked, blocked, invalid, unavailable
}

nonisolated struct TaskLinkDiagnostic: Equatable, Sendable {
    let code: String
    let taskIds: [UUID]
    let edgeId: UUID?
    let physicalKey: Data
}

nonisolated struct TaskLinkDuplicateResolution: Equatable, Sendable {
    let path: [UUID]
    let canonical: UUID?
    let diagnostic: String?
}

nonisolated struct TaskLinkGraphBudget: Sendable {
    let deadline: ContinuousClock.Instant
    let maximumBytes: Int
    let checkpoint: (@Sendable () throws -> Void)?

    init(deadline: ContinuousClock.Instant = .now.advanced(by: .seconds(5)),
         maximumBytes: Int = 16 * 1_024 * 1_024, checkpoint: (@Sendable () throws -> Void)? = nil) {
        self.deadline = deadline
        self.maximumBytes = maximumBytes
        self.checkpoint = checkpoint
    }

    func check() throws {
        guard ContinuousClock.now < deadline else { throw TaskLinkGraphError.deadlineExceeded }
        try checkpoint?()
    }
}

nonisolated enum TaskLinkGraphError: Error {
    case deadlineExceeded, capacityExceeded, invalidDelta, missingSource, ambiguousIdentity
    case invalidOccurrence, repairUnavailable, revisionConflict, invalidGraph, endpointPreconditions
}

nonisolated struct TaskLinkGraphView: Sendable {
    let tasks: [TaskLinkTaskValue]
    let occurrences: [TaskLinkOccurrenceValue]
    let removalEvidence: [TaskLinkRemovalValue]
    let evaluationInstant: Date
    let tasksById: [UUID: [TaskLinkTaskValue]]
    let occurrencesById: [UUID: [TaskLinkOccurrenceValue]]
    let incidence: [UUID: [TaskLinkOccurrenceValue]]
    let diagnostics: [TaskLinkDiagnostic]
    let cyclicTasks: Set<UUID>
    let blockers: [UUID: TaskLinkBlockerAssessment]
    let retainedBytes: Int
    let invalidOccurrences: Set<Data>
    let recognizedRemovals: [UUID: [TaskLinkRemovalValue]]

    func withRetainedBytes(_ bytes: Int) -> TaskLinkGraphView {
        TaskLinkGraphView(tasks: tasks, occurrences: occurrences, removalEvidence: removalEvidence,
            evaluationInstant: evaluationInstant, tasksById: tasksById, occurrencesById: occurrencesById,
            incidence: incidence, diagnostics: diagnostics, cyclicTasks: cyclicTasks, blockers: blockers,
            retainedBytes: bytes, invalidOccurrences: invalidOccurrences, recognizedRemovals: recognizedRemovals)
    }

    func assessment(for id: UUID) -> TaskLinkBlockerAssessment { blockers[id] ?? .unavailable }
}
