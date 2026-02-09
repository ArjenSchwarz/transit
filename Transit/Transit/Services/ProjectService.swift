//
//  ProjectService.swift
//  Transit
//
//  Service for project CRUD operations.
//

import Foundation
import SwiftData
import SwiftUI

@MainActor @Observable
final class ProjectService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Create a new project.
    func createProject(
        name: String,
        description: String,
        gitRepo: String?,
        color: Color
    ) throws -> Project {
        let project = Project(name: name, description: description, gitRepo: gitRepo, color: color)
        modelContext.insert(project)
        try modelContext.save()
        return project
    }

    /// Find project by UUID.
    func findProject(id: UUID) throws -> Project? {
        let predicate = #Predicate<Project> { $0.id == id }
        let descriptor = FetchDescriptor(predicate: predicate)
        return try modelContext.fetch(descriptor).first
    }

    /// Find project by name (case-insensitive, trimmed).
    /// Returns nil if not found, throws if ambiguous.
    func findProject(name: String) throws -> Project? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let all = try modelContext.fetch(FetchDescriptor<Project>())
        let matches = all.filter { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }

        switch matches.count {
        case 0:
            return nil
        case 1:
            return matches[0]
        default:
            throw ProjectServiceError.ambiguousProject(count: matches.count, name: trimmed)
        }
    }

    /// Count of non-terminal tasks for a project.
    func activeTaskCount(for project: Project) -> Int {
        (project.tasks ?? []).filter { !$0.status.isTerminal }.count
    }
}

enum ProjectServiceError: Error, LocalizedError {
    case ambiguousProject(count: Int, name: String)

    var errorDescription: String? {
        switch self {
        case .ambiguousProject(let count, let name):
            return "\(count) projects match '\(name)'. Use projectId instead."
        }
    }
}
