import Foundation
import SwiftData
import SwiftUI

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var projectDescription: String = ""
    var gitRepo: String?
    var colorHex: String = "#007AFF"

    @Relationship(deleteRule: .nullify, inverse: \TransitTask.project)
    var tasks: [TransitTask]?

    @MainActor
    var color: Color {
        get { Color(hex: colorHex) }
        set { colorHex = newValue.hexString }
    }

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        gitRepo: String? = nil,
        colorHex: String
    ) {
        self.id = id
        self.name = name
        self.projectDescription = description
        self.gitRepo = gitRepo
        self.colorHex = colorHex
        self.tasks = nil
    }

    @MainActor
    convenience init(
        id: UUID = UUID(),
        name: String,
        description: String,
        gitRepo: String? = nil,
        color: Color
    ) {
        self.init(
            id: id,
            name: name,
            description: description,
            gitRepo: gitRepo,
            colorHex: color.hexString
        )
    }
}
