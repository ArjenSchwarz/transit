import Foundation
import SwiftData

@Model
final class Comment {
    var id: UUID = UUID()
    var content: String = ""
    var authorName: String = ""
    var isAgent: Bool = false
    var creationDate: Date = Date()

    var task: TransitTask?

    init(
        content: String,
        authorName: String,
        isAgent: Bool,
        task: TransitTask
    ) {
        self.id = UUID()
        self.content = content
        self.authorName = authorName
        self.isAgent = isAgent
        self.creationDate = Date.now
        self.task = task
    }
}
