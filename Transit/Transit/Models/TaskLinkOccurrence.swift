import Foundation
import SwiftData

/// One active physical occurrence. Scalar endpoints preserve dangling and
/// ambiguous imported evidence without task relationships or delete cascades.
/// Storage defaults support additive schema compatibility, not graph validity.
@Model
nonisolated final class TaskLinkOccurrence {
    private(set) var id: UUID = UUID()
    private(set) var kindRawValue: String = ""
    private(set) var sourceTaskID: UUID = UUID()
    private(set) var targetTaskID: UUID = UUID()
    private(set) var createdAt: Date = Date()

    init(id: UUID, kindRawValue: String, sourceTaskID: UUID, targetTaskID: UUID, createdAt: Date) {
        self.id = id
        self.kindRawValue = kindRawValue
        self.sourceTaskID = sourceTaskID
        self.targetTaskID = targetTaskID
        self.createdAt = createdAt
    }
}
