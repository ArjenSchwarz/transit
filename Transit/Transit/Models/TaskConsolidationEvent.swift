import Foundation
import SwiftData

/// Immutable operation evidence survives task deletion and receipt expiration.
@Model
final class TaskConsolidationEvent {
    private(set) var id: UUID = UUID()
    private(set) var operationId: UUID = UUID()
    private(set) var kindRawValue: String = ""
    private(set) var createdAt: Date = Date()
    private(set) var originScopeId: String = ""
    private(set) var survivorTaskId: UUID = UUID()
    private(set) var candidate1: UUID?
    private(set) var candidate2: UUID?
    private(set) var candidate3: UUID?
    private(set) var candidate4: UUID?
    private(set) var candidate5: UUID?
    private(set) var payloadJSON: String = ""

    init(id: UUID, operationId: UUID, kindRawValue: String, createdAt: Date,
         originScopeId: String, survivorTaskId: UUID, candidateTaskIds: [UUID], payloadJSON: String) {
        self.id = id
        self.operationId = operationId
        self.kindRawValue = kindRawValue
        self.createdAt = createdAt
        self.originScopeId = originScopeId
        self.survivorTaskId = survivorTaskId
        self.candidate1 = candidateTaskIds.indices.contains(0) ? candidateTaskIds[0] : nil
        self.candidate2 = candidateTaskIds.indices.contains(1) ? candidateTaskIds[1] : nil
        self.candidate3 = candidateTaskIds.indices.contains(2) ? candidateTaskIds[2] : nil
        self.candidate4 = candidateTaskIds.indices.contains(3) ? candidateTaskIds[3] : nil
        self.candidate5 = candidateTaskIds.indices.contains(4) ? candidateTaskIds[4] : nil
        self.payloadJSON = payloadJSON
    }
}
