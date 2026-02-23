import SwiftData
import Foundation

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var projectDescription: String = ""
    var gitRepo: String?
    var colorHex: String = ""

    @Relationship(deleteRule: .nullify, inverse: \TransitTask.project)
    var tasks: [TransitTask]?

    @Relationship(deleteRule: .cascade, inverse: \Milestone.project)
    var milestones: [Milestone]?

    init(name: String, description: String, gitRepo: String?, colorHex: String) {
        self.id = UUID()
        self.name = name
        self.projectDescription = description
        self.gitRepo = gitRepo
        self.colorHex = colorHex
    }
}
