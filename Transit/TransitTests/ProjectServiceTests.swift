import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct ProjectServiceTests {

    // MARK: - Helpers

    private func makeService() throws -> (ProjectService, ModelContext) {
        let context = try TestModelContainer.newContext()
        let service = ProjectService(modelContext: context)
        return (service, context)
    }

    // MARK: - createProject

    @Test func createProjectCreatesProjectWithCorrectFields() throws {
        let (service, _) = try makeService()

        let project = try service.createProject(
            name: "My Project",
            description: "A description",
            gitRepo: "https://github.com/user/repo",
            colorHex: "#FF5500"
        )

        #expect(project.name == "My Project")
        #expect(project.projectDescription == "A description")
        #expect(project.gitRepo == "https://github.com/user/repo")
        #expect(project.colorHex == "#FF5500")
    }

    // MARK: - createProject duplicate name prevention

    @Test func createProjectWithDuplicateNameThrows() throws {
        let (service, _) = try makeService()
        try service.createProject(name: "Transit", description: "First", gitRepo: nil, colorHex: "#000000")

        #expect(throws: ProjectMutationError.self) {
            try service.createProject(name: "Transit", description: "Second", gitRepo: nil, colorHex: "#111111")
        }
    }

    @Test func createProjectWithDuplicateNameCaseInsensitiveThrows() throws {
        let (service, _) = try makeService()
        try service.createProject(name: "Transit", description: "First", gitRepo: nil, colorHex: "#000000")

        #expect(throws: ProjectMutationError.self) {
            try service.createProject(name: "transit", description: "Second", gitRepo: nil, colorHex: "#111111")
        }
    }

    @Test func createProjectWithDuplicateNameWhitespaceVariantThrows() throws {
        let (service, _) = try makeService()
        try service.createProject(name: "Transit", description: "First", gitRepo: nil, colorHex: "#000000")

        #expect(throws: ProjectMutationError.self) {
            try service.createProject(name: "  Transit  ", description: "Second", gitRepo: nil, colorHex: "#111111")
        }
    }

    // MARK: - createProject persists via save (T-117)

    @Test func createProjectPersistsViaSave() throws {
        let (service, context) = try makeService()
        let project = try service.createProject(
            name: "Persisted",
            description: "Should be saved",
            gitRepo: nil,
            colorHex: "#000000"
        )

        // Verify the project is fetchable from the context after creation,
        // confirming that createProject calls context.save() (not try?).
        let projectID = project.id
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == projectID }
        )
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Persisted")

        // Verify no pending changes remain — the save was committed.
        #expect(context.hasChanges == false)
    }

    @Test func createProjectWithDifferentNameSucceeds() throws {
        let (service, _) = try makeService()
        try service.createProject(name: "Transit", description: "First", gitRepo: nil, colorHex: "#000000")

        let second = try service.createProject(name: "Orbit", description: "Second", gitRepo: nil, colorHex: "#111111")
        #expect(second.name == "Orbit")
    }

    // MARK: - projectNameExists

    @Test func projectNameExistsReturnsTrueForExactMatch() throws {
        let (service, _) = try makeService()
        try service.createProject(name: "Transit", description: "Desc", gitRepo: nil, colorHex: "#000000")

        #expect(service.projectNameExists("Transit") == true)
    }

    @Test func projectNameExistsReturnsTrueForCaseInsensitiveMatch() throws {
        let (service, _) = try makeService()
        try service.createProject(name: "Transit", description: "Desc", gitRepo: nil, colorHex: "#000000")

        #expect(service.projectNameExists("transit") == true)
    }

    @Test func projectNameExistsReturnsFalseWhenNoMatch() throws {
        let (service, _) = try makeService()
        try service.createProject(name: "Transit", description: "Desc", gitRepo: nil, colorHex: "#000000")

        #expect(service.projectNameExists("Orbit") == false)
    }

    @Test func projectNameExistsExcludesSpecifiedProject() throws {
        let (service, _) = try makeService()
        let project = try service.createProject(name: "Transit", description: "Desc", gitRepo: nil, colorHex: "#000000")

        // Same name should not conflict when the project itself is excluded (rename to same name).
        #expect(service.projectNameExists("Transit", excluding: project.id) == false)
    }

    @Test func projectNameExistsDetectsConflictWithOtherProject() throws {
        let (service, _) = try makeService()
        let first = try service.createProject(name: "Transit", description: "Desc", gitRepo: nil, colorHex: "#000000")
        try service.createProject(name: "Orbit", description: "Desc", gitRepo: nil, colorHex: "#111111")

        // "Orbit" exists and is not the excluded project, so this should return true.
        #expect(service.projectNameExists("Orbit", excluding: first.id) == true)
    }

    @Test func createProjectTrimsWhitespaceFromName() throws {
        let (service, _) = try makeService()
        let project = try service.createProject(
            name: "  Transit  ",
            description: "Desc",
            gitRepo: nil,
            colorHex: "#000000"
        )

        #expect(project.name == "Transit")
    }

    // MARK: - findProject by ID

    @Test func findProjectByIDReturnsCorrectProject() throws {
        let (service, _) = try makeService()
        let project = try service.createProject(name: "Target", description: "Desc", gitRepo: nil, colorHex: "#000000")

        let result = service.findProject(id: project.id)

        switch result {
        case .success(let found):
            #expect(found.name == "Target")
        case .failure(let error):
            Issue.record("Expected success but got \(error)")
        }
    }

    @Test func findProjectByIDReturnsNotFoundForNonExistentID() throws {
        let (service, _) = try makeService()

        let result = service.findProject(id: UUID())

        switch result {
        case .success:
            Issue.record("Expected notFound failure")
        case .failure(let error):
            guard case .notFound = error else {
                Issue.record("Expected notFound but got \(error)")
                return
            }
        }
    }

    // MARK: - findProject by name

    @Test func findProjectByNameCaseInsensitiveReturnsCorrectProject() throws {
        let (service, _) = try makeService()
        try service.createProject(name: "Transit", description: "Desc", gitRepo: nil, colorHex: "#000000")

        let result = service.findProject(name: "transit")

        switch result {
        case .success(let found):
            #expect(found.name == "Transit")
        case .failure(let error):
            Issue.record("Expected success but got \(error)")
        }
    }

    @Test func findProjectByNameWithWhitespaceWorks() throws {
        let (service, _) = try makeService()
        try service.createProject(name: "Transit", description: "Desc", gitRepo: nil, colorHex: "#000000")

        let result = service.findProject(name: "  Transit  ")

        switch result {
        case .success(let found):
            #expect(found.name == "Transit")
        case .failure(let error):
            Issue.record("Expected success but got \(error)")
        }
    }

    @Test func findProjectWithAmbiguousNameReturnsAmbiguousError() throws {
        let (service, context) = try makeService()
        // Insert duplicates directly to simulate pre-existing data (e.g. from CloudKit sync).
        // ProjectService.createProject() now prevents this, but findProject must still
        // handle it gracefully for data that predates the uniqueness check.
        let first = Project(name: "Transit", description: "First", gitRepo: nil, colorHex: "#000000")
        let second = Project(name: "transit", description: "Second", gitRepo: nil, colorHex: "#111111")
        context.insert(first)
        context.insert(second)

        let result = service.findProject(name: "Transit")

        switch result {
        case .success:
            Issue.record("Expected ambiguous failure")
        case .failure(let error):
            guard case .ambiguous = error else {
                Issue.record("Expected ambiguous but got \(error)")
                return
            }
        }
    }

    @Test func findProjectByNameReturnsNotFoundWhenNoMatch() throws {
        let (service, _) = try makeService()
        try service.createProject(name: "Transit", description: "Desc", gitRepo: nil, colorHex: "#000000")

        let result = service.findProject(name: "Orbit")

        switch result {
        case .success:
            Issue.record("Expected notFound failure")
        case .failure(let error):
            guard case .notFound = error else {
                Issue.record("Expected notFound but got \(error)")
                return
            }
        }
    }

    // MARK: - findProject with no identifier

    @Test func findProjectWithNoIdentifierReturnsNoIdentifierError() throws {
        let (service, _) = try makeService()

        let result = service.findProject()

        switch result {
        case .success:
            Issue.record("Expected noIdentifier failure")
        case .failure(let error):
            guard case .noIdentifier = error else {
                Issue.record("Expected noIdentifier but got \(error)")
                return
            }
        }
    }

    // MARK: - activeTaskCount

    @Test func activeTaskCountReturnsCountOfNonTerminalTasks() throws {
        let (service, context) = try makeService()
        let project = try service.createProject(name: "P", description: "Desc", gitRepo: nil, colorHex: "#000000")

        let activeTask = TransitTask(name: "Active", type: .feature, project: project, displayID: .provisional)
        StatusEngine.initializeNewTask(activeTask)
        context.insert(activeTask)

        let inProgressTask = TransitTask(name: "In Progress", type: .bug, project: project, displayID: .provisional)
        StatusEngine.initializeNewTask(inProgressTask)
        StatusEngine.applyTransition(task: inProgressTask, to: .inProgress)
        context.insert(inProgressTask)

        let doneTask = TransitTask(name: "Done", type: .chore, project: project, displayID: .provisional)
        StatusEngine.initializeNewTask(doneTask)
        StatusEngine.applyTransition(task: doneTask, to: .done)
        context.insert(doneTask)

        let abandonedTask = TransitTask(name: "Abandoned", type: .research, project: project, displayID: .provisional)
        StatusEngine.initializeNewTask(abandonedTask)
        StatusEngine.applyTransition(task: abandonedTask, to: .abandoned)
        context.insert(abandonedTask)

        #expect(service.activeTaskCount(for: project) == 2)
    }

    @Test func activeTaskCountReturnsZeroForProjectWithNoTasks() throws {
        let (service, _) = try makeService()
        let project = try service.createProject(name: "Empty", description: "Desc", gitRepo: nil, colorHex: "#000000")

        #expect(service.activeTaskCount(for: project) == 0)
    }
}
