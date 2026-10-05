import Foundation

nonisolated struct ConsolidationOriginal: Codable, Equatable, Sendable {
    let id: UUID
    let physicalKey: Data
    let projectId: UUID
    let projectPhysicalKey: Data
    let fields: TaskConsolidationRawFields
    let revision: String
    let recordJSON: Data
}

nonisolated enum ConsolidationDescriptionEdit: Codable, Equatable, Sendable {
    case omitted
    case replace(String?)
}

nonisolated struct ConsolidationEdits: Codable, Equatable, Sendable {
    var description: ConsolidationDescriptionEdit = .omitted
    var metadata: [String: String]?
}

nonisolated struct ConsolidationDisposition: Codable, Equatable, Sendable {
    struct Reference: Codable, Equatable, Sendable {
        let sourceDetail: String
        let survivorField: String
    }
    var incorporated: [Reference] = []
    var retainedExplanation: String?
}

nonisolated struct ConsolidationRequest: Codable, Equatable, Sendable {
    let survivorTaskId: UUID
    let candidateTaskIds: [UUID]
    let reason: String
    let preservation: [String: ConsolidationDisposition]
    var survivorEdits = ConsolidationEdits()
}

nonisolated struct ConsolidationPlan: Sendable {
    let request: ConsolidationRequest
    let originals: [ConsolidationOriginal]
    let changes: [TaskConsolidationReviewedTaskChange]
    let links: TaskLinkPlan
    let retainedOccurrences: [TaskConsolidationOccurrence]
    let reviewRevision: String
}

nonisolated struct ConsolidationReversalPlan: Sendable {
    let apply: TaskConsolidationPayload
    let changes: [TaskConsolidationReviewedTaskChange]
    let links: TaskLinkPlan
    let operationRevision: String
    let reversalId: UUID?
}

nonisolated enum ConsolidationPlanningError: Error {
    case invalidInput, unavailableEvidence, wrongProject, invalidCanonical, revisionConflict, alreadyReversed
}

extension ConsolidationDisposition {
    private nonisolated enum CodingKeys: String, CodingKey { case incorporated, retainedExplanation }

    nonisolated init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        incorporated = try values.decodeIfPresent([Reference].self, forKey: .incorporated) ?? []
        retainedExplanation = try values.decodeIfPresent(String.self, forKey: .retainedExplanation)
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        if !incorporated.isEmpty { try values.encode(incorporated, forKey: .incorporated) }
        try values.encodeIfPresent(retainedExplanation, forKey: .retainedExplanation)
    }
}
