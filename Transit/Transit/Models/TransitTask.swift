import Foundation
import SwiftData

@Model
final class TransitTask {
    var id: UUID = UUID()
    var permanentDisplayId: Int?
    var name: String = ""
    var taskDescription: String?
    var statusRawValue: String = "idea"
    var typeRawValue: String = "feature"
    var creationDate: Date = Date()
    var lastStatusChangeDate: Date = Date()
    var completionDate: Date?
    var metadataJSON: String?

    var project: Project?
    var milestone: Milestone?

    @Relationship(deleteRule: .cascade, inverse: \Comment.task)
    var comments: [Comment]?

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRawValue) ?? .idea }
        set { statusRawValue = newValue.rawValue }
    }

    var type: TaskType {
        get { TaskType(rawValue: typeRawValue) ?? .feature }
        set { typeRawValue = newValue.rawValue }
    }

    var displayID: DisplayID {
        if let id = permanentDisplayId {
            return .permanent(id)
        }
        return .provisional
    }

    var metadata: [String: String] {
        get {
            guard let data = metadataJSON?.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return dict
        }
        set {
            if newValue.isEmpty {
                metadataJSON = nil
            } else {
                metadataJSON = try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)
            }
        }
    }

    var shareText: String {
        shareText(comments: [])
    }

    func shareText(comments: [Comment]) -> String {
        let typeName = type.rawValue.capitalized
        var text = "# \(displayID.formatted) \(name) (\(typeName))\n"

        if let project {
            text += "Project: \(project.name)\n"
        }

        if let taskDescription, !taskDescription.isEmpty {
            text += "\n\(taskDescription)\n"
        }

        let metadata = metadata
        if !metadata.isEmpty {
            text += "\n"
            for (key, value) in metadata.sorted(by: { $0.key < $1.key }) {
                text += "\(key): \(value)\n"
            }
        }

        if !comments.isEmpty {
            text += "\n## Comments\n\n"
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            for comment in comments {
                let authorLabel = comment.isAgent
                    ? "\(comment.authorName) [Agent]"
                    : comment.authorName
                let timestamp = formatter.string(from: comment.creationDate)
                text += "**\(authorLabel)** (\(timestamp)):\n\(comment.content)\n\n"
            }
        }

        return text
    }

    init(
        name: String,
        description: String? = nil,
        type: TaskType,
        project: Project,
        displayID: DisplayID,
        metadata: [String: String]? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.taskDescription = description
        self.typeRawValue = type.rawValue
        self.project = project
        self.creationDate = Date.now
        self.lastStatusChangeDate = Date.now
        self.statusRawValue = TaskStatus.idea.rawValue

        switch displayID {
        case .permanent(let id):
            self.permanentDisplayId = id
        case .provisional:
            self.permanentDisplayId = nil
        }

        if let metadata, !metadata.isEmpty {
            self.metadataJSON = try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        }
    }
}
