import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class ProjectService: @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case invalidName
        case invalidDescription
        case projectNotFound
        case ambiguousProject
        case missingLookup
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func createProject(
        name: String,
        description: String,
        gitRepo: String? = nil,
        color: Color
    ) throws -> Project {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedName.isEmpty else {
            throw Error.invalidName
        }

        guard !normalizedDescription.isEmpty else {
            throw Error.invalidDescription
        }

        let project = Project(
            name: normalizedName,
            description: normalizedDescription,
            gitRepo: normalizeOptionalText(gitRepo),
            color: color
        )
        modelContext.insert(project)
        try modelContext.save()
        return project
    }

    func findProject(id: UUID? = nil, name: String? = nil) throws -> Project {
        if let id {
            return try findProjectByID(id)
        }

        if let name {
            return try findProjectByName(name)
        }

        throw Error.missingLookup
    }

    func activeTaskCount(for project: Project) throws -> Int {
        let projectID = project.id
        let predicate = #Predicate<TransitTask> { task in
            task.project?.id == projectID
        }

        let descriptor = FetchDescriptor(predicate: predicate)
        let tasks = try modelContext.fetch(descriptor)

        var activeCount = 0
        for task in tasks where !task.status.isTerminal {
            activeCount += 1
        }
        return activeCount
    }

    private func findProjectByID(_ id: UUID) throws -> Project {
        let predicate = #Predicate<Project> { project in
            project.id == id
        }
        let descriptor = FetchDescriptor(predicate: predicate)

        guard let project = try modelContext.fetch(descriptor).first else {
            throw Error.projectNotFound
        }

        return project
    }

    private func findProjectByName(_ name: String) throws -> Project {
        let normalizedTarget = normalizeLookup(name)
        let projects = try modelContext.fetch(FetchDescriptor<Project>())

        var matches: [Project] = []
        matches.reserveCapacity(projects.count)

        for project in projects where normalizeLookup(project.name) == normalizedTarget {
            matches.append(project)
            if matches.count > 1 {
                throw Error.ambiguousProject
            }
        }

        guard let match = matches.first else {
            throw Error.projectNotFound
        }

        return match
    }

    private func normalizeLookup(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func normalizeOptionalText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
