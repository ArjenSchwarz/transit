#if os(macOS)
import Foundation
import SwiftData

@MainActor
enum MCPReadCommentFetch {
    /// Nil retains complete-portfolio orphan coverage. Selected reads preserve
    /// the existing logical-ID closure, including foreign physical duplicates;
    /// canonical revisions and physical comment ownership are indexed afterward.
    static func descriptor(taskIDs: [UUID]?) -> FetchDescriptor<Comment> {
        var descriptor = FetchDescriptor<Comment>()
        if let ids = taskIDs {
            descriptor.predicate = #Predicate<Comment> { comment in
                comment.task.flatMap { ids.contains($0.id) } ?? false
            }
        }
        descriptor.includePendingChanges = false
        return descriptor
    }
}
#endif
