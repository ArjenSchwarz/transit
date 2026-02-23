import Foundation
import SwiftData

@Model
final class Milestone {
    var id: UUID = UUID()
    var permanentDisplayId: Int?
    var name: String = ""
    var milestoneDescription: String?
    var statusRawValue: String = "open"
    var creationDate: Date = Date()
    var lastStatusChangeDate: Date = Date()
    var completionDate: Date?

    var project: Project?

    @Relationship(deleteRule: .nullify, inverse: \TransitTask.milestone)
    var tasks: [TransitTask]?

    var status: MilestoneStatus {
        get { MilestoneStatus(rawValue: statusRawValue) ?? .open }
        set { statusRawValue = newValue.rawValue }
    }

    var displayID: DisplayID {
        if let id = permanentDisplayId {
            return .permanent(id)
        }
        return .provisional
    }

    init(name: String, description: String? = nil, project: Project, displayID: DisplayID) {
        self.id = UUID()
        self.name = name
        self.milestoneDescription = description
        self.project = project
        self.creationDate = Date.now
        self.lastStatusChangeDate = Date.now
        self.statusRawValue = MilestoneStatus.open.rawValue

        switch displayID {
        case .permanent(let id):
            self.permanentDisplayId = id
        case .provisional:
            self.permanentDisplayId = nil
        }
    }
}
