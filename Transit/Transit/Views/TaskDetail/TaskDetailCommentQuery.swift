import Foundation
import SwiftData

/// The reactive comment feed for one open task-detail view.
///
/// Querying from `Comment` keeps the optional CloudKit relationship compatible,
/// and the UUID tiebreaker makes equal creation timestamps deterministic.
enum TaskDetailCommentQuery {
    static func descriptor(for taskID: UUID) -> FetchDescriptor<Comment> {
        FetchDescriptor<Comment>(
            predicate: #Predicate { $0.task?.id == taskID },
            sortBy: [
                SortDescriptor(\Comment.creationDate, order: .forward),
                SortDescriptor(\Comment.id, order: .forward)
            ]
        )
    }
}
