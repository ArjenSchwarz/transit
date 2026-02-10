//
//  Project.swift
//  Transit
//
//  Project model for organizing tasks.
//

import Foundation
import SwiftData
import SwiftUI

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var projectDescription: String = ""  // "description" is reserved in some contexts
    var gitRepo: String?
    var colorHex: String = "" // Stored as hex string for CloudKit compatibility

    @Relationship(deleteRule: .nullify, inverse: \TransitTask.project)
    var tasks: [TransitTask]?

    // Computed property for UI access
    var color: Color {
        Color(hex: colorHex)
    }

    init(name: String, description: String, gitRepo: String?, color: Color) {
        self.id = UUID()
        self.name = name
        self.projectDescription = description
        self.gitRepo = gitRepo
        self.colorHex = color.hexString
    }
}
