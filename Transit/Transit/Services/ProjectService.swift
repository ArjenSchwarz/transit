import Foundation
import SwiftData

/// Errors returned by `ProjectService.findProject` when a project cannot be
/// uniquely identified. Designed to be translated into intent error codes
/// (TASK 41) when formatting JSON responses.
enum ProjectLookupError: Error {
    case notFound(hint: String)
    case ambiguous(hint: String)
    case noIdentifier
}

/// Errors returned by project mutation operations (create, rename).
enum ProjectMutationError: Error {
    case duplicateName(String)
}

/// Manages project creation, lookup, and task counting.
@MainActor @Observable
final class ProjectService {

    let context: ModelContext

    init(modelContext: ModelContext) {
        self.context = modelContext
    }

    // MARK: - Creation

    /// Creates and inserts a new project.
    ///
    /// Throws `ProjectMutationError.duplicateName` if a project with the same
    /// name (case-insensitive) already exists.
    @discardableResult
    func createProject(name: String, description: String, gitRepo: String?, colorHex: String) throws -> Project {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if projectNameExists(trimmedName) {
            throw ProjectMutationError.duplicateName(trimmedName)
        }
        let project = Project(name: trimmedName, description: description, gitRepo: gitRepo, colorHex: colorHex)
        context.insert(project)
        try? context.save()
        return project
    }

    // MARK: - Lookup

    /// Finds a project by UUID or by name (case-insensitive, trimmed).
    ///
    /// - If `id` is provided, performs an exact UUID match.
    /// - If `name` is provided, performs a case-insensitive search with trimmed whitespace.
    /// - If neither is provided, returns `.noIdentifier`.
    ///
    /// Returns `.success(project)` for a unique match, or a `ProjectLookupError` otherwise.
    func findProject(id: UUID? = nil, name: String? = nil) -> Result<Project, ProjectLookupError> {
        if let id {
            let descriptor = FetchDescriptor<Project>(
                predicate: #Predicate { $0.id == id }
            )
            guard let project = try? context.fetch(descriptor).first else {
                return .failure(.notFound(hint: "No project with ID \(id.uuidString)"))
            }
            return .success(project)
        }

        if let rawName = name {
            let trimmed = rawName.trimmingCharacters(in: .whitespaces)
            // SwiftData predicates support .localizedStandardContains but not
            // arbitrary case-insensitive equality. Fetch all and filter in memory
            // for exact case-insensitive match (project count is small).
            let descriptor = FetchDescriptor<Project>()
            let allProjects = (try? context.fetch(descriptor)) ?? []
            let matches = allProjects.filter {
                $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
            }

            switch matches.count {
            case 0:
                return .failure(.notFound(hint: "No project named \"\(trimmed)\""))
            case 1:
                return .success(matches[0])
            default:
                return .failure(.ambiguous(hint: "\(matches.count) projects match \"\(trimmed)\""))
            }
        }

        return .failure(.noIdentifier)
    }

    // MARK: - Validation

    /// Checks whether a project with the given name already exists (case-insensitive).
    ///
    /// When `excluding` is provided, the project with that ID is ignored — this
    /// supports the rename scenario where the project's own current name should
    /// not count as a conflict.
    func projectNameExists(_ name: String, excluding projectId: UUID? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let descriptor = FetchDescriptor<Project>()
        let allProjects = (try? context.fetch(descriptor)) ?? []
        return allProjects.contains { project in
            if let projectId, project.id == projectId { return false }
            return project.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    // MARK: - Queries

    /// Returns the number of tasks in non-terminal statuses for a project.
    func activeTaskCount(for project: Project) -> Int {
        let tasks = project.tasks ?? []
        return tasks.filter { !$0.status.isTerminal }.count
    }
}
