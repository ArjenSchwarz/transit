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

/// Manages project creation, lookup, and task counting.
@MainActor @Observable
final class ProjectService {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Creation

    /// Creates and inserts a new project.
    @discardableResult
    func createProject(name: String, description: String, gitRepo: String?, colorHex: String) -> Project {
        let project = Project(name: name, description: description, gitRepo: gitRepo, colorHex: colorHex)
        modelContext.insert(project)
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
            guard let project = try? modelContext.fetch(descriptor).first else {
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
            let allProjects = (try? modelContext.fetch(descriptor)) ?? []
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

    // MARK: - Queries

    /// Returns the number of tasks in non-terminal statuses for a project.
    func activeTaskCount(for project: Project) -> Int {
        let tasks = project.tasks ?? []
        return tasks.filter { !$0.status.isTerminal }.count
    }
}
