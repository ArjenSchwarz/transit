//
//  TransitTask.swift
//  Transit
//
//  Task model with status progression and CloudKit sync.
//

import Foundation
import SwiftData

@Model
final class TransitTask {
    var id: UUID = UUID()
    var permanentDisplayId: Int?  // nil when provisional
    var name: String = ""
    var taskDescription: String?
    var statusRawValue: String  = "idea"  // Stored as raw string for CloudKit
    var typeRawValue: String  = "feature"    // Stored as raw string for CloudKit
    var creationDate: Date  = Date()      // Set once at creation, used for promotion ordering
    var lastStatusChangeDate: Date = Date()
    var completionDate: Date?
    var metadataJSON: String?     // Stored as JSON string for CloudKit compatibility

    var project: Project?

    // Computed properties
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
            metadataJSON = try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)
        }
    }

    init(
        name: String,
        description: String?,
        type: TaskType,
        project: Project,
        permanentDisplayId: Int?,
        metadata: [String: String]?
    ) {
        self.id = UUID()
        self.name = name
        self.taskDescription = description
        self.typeRawValue = type.rawValue
        self.statusRawValue = TaskStatus.idea.rawValue
        self.project = project
        self.permanentDisplayId = permanentDisplayId
        self.creationDate = Date.now
        self.lastStatusChangeDate = Date.now
        if let metadata {
            self.metadataJSON = try? String(data: JSONEncoder().encode(metadata), encoding: .utf8)
        }
    }
}
