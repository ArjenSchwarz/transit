import Foundation
import SwiftData

@Model
final class TransitTask {
    var id: UUID
    var permanentDisplayId: Int?
    var name: String
    var taskDescription: String?
    var statusRawValue: String
    var typeRawValue: String
    var creationDate: Date
    var lastStatusChangeDate: Date
    var completionDate: Date?
    var metadataJSON: String?

    var project: Project?

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRawValue) ?? .idea }
        set { statusRawValue = newValue.rawValue }
    }

    var type: TaskType {
        get { TaskType(rawValue: typeRawValue) ?? .feature }
        set { typeRawValue = newValue.rawValue }
    }

    var displayID: DisplayID {
        if let permanentDisplayId {
            return .permanent(permanentDisplayId)
        }
        return .provisional
    }

    var metadata: [String: String]? {
        get {
            guard let metadataJSON, let data = metadataJSON.data(using: .utf8) else {
                return nil
            }

            return try? JSONDecoder().decode([String: String].self, from: data)
        }
        set {
            guard let newValue else {
                metadataJSON = nil
                return
            }

            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else {
                metadataJSON = nil
                return
            }
            metadataJSON = json
        }
    }

    init(
        id: UUID = UUID(),
        permanentDisplayId: Int? = nil,
        name: String,
        description: String? = nil,
        status: TaskStatus = .idea,
        type: TaskType = .feature,
        creationDate: Date = .now,
        lastStatusChangeDate: Date = .now,
        completionDate: Date? = nil,
        metadata: [String: String]? = nil,
        project: Project? = nil
    ) {
        self.id = id
        self.permanentDisplayId = permanentDisplayId
        self.name = name
        self.taskDescription = description
        self.statusRawValue = status.rawValue
        self.typeRawValue = type.rawValue
        self.creationDate = creationDate
        self.lastStatusChangeDate = lastStatusChangeDate
        self.completionDate = completionDate
        self.project = project

        if let metadata,
           let data = try? JSONEncoder().encode(metadata),
           let json = String(data: data, encoding: .utf8) {
            self.metadataJSON = json
        } else {
            self.metadataJSON = nil
        }
    }
}
