import Foundation
import SwiftData

/// Bounded exact-removal recognition stored separately from the deleted active
/// occurrence. Expiry never changes active incidence or platform sync history.
/// Raw immutable values preserve malformed imports for later diagnostics.
@Model
nonisolated final class TaskLinkRemovalEvidence {
    private(set) var id: UUID = UUID()
    private(set) var edgeId: UUID = UUID()
    private(set) var kindRawValue: String = ""
    private(set) var sourceTaskID: UUID = UUID()
    private(set) var targetTaskID: UUID = UUID()
    private(set) var createdAt: Date = Date()
    private(set) var occurrenceRevision: String = ""
    private(set) var removedAt: Date = Date()

    init(id: UUID, edgeId: UUID, kindRawValue: String, sourceTaskID: UUID, targetTaskID: UUID,
         createdAt: Date, occurrenceRevision: String, removedAt: Date) {
        self.id = id
        self.edgeId = edgeId
        self.kindRawValue = kindRawValue
        self.sourceTaskID = sourceTaskID
        self.targetTaskID = targetTaskID
        self.createdAt = createdAt
        self.occurrenceRevision = occurrenceRevision
        self.removedAt = removedAt
    }
}
