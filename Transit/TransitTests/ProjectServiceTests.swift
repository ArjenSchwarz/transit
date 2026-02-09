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

        let project = service.createProject(
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

    // MARK: - findProject by ID

    @Test func findProjectByIDReturnsCorrectProject() throws {
        let (service, _) = try makeService()
        let project = service.createProject(name: "Target", description: "Desc", gitRepo: nil, colorHex: "#000000")

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
        service.createProject(name: "Transit", description: "Desc", gitRepo: nil, colorHex: "#000000")

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
        service.createProject(name: "Transit", description: "Desc", gitRepo: nil, colorHex: "#000000")

        let result = service.findProject(name: "  Transit  ")

        switch result {
        case .success(let found):
            #expect(found.name == "Transit")
        case .failure(let error):
            Issue.record("Expected success but got \(error)")
        }
    }

    @Test func findProjectWithAmbiguousNameReturnsAmbiguousError() throws {
        let (service, _) = try makeService()
        service.createProject(name: "Transit", description: "First", gitRepo: nil, colorHex: "#000000")
        service.createProject(name: "transit", description: "Second", gitRepo: nil, colorHex: "#111111")

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
        service.createProject(name: "Transit", description: "Desc", gitRepo: nil, colorHex: "#000000")

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
        let project = service.createProject(name: "P", description: "Desc", gitRepo: nil, colorHex: "#000000")

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
        let project = service.createProject(name: "Empty", description: "Desc", gitRepo: nil, colorHex: "#000000")

        #expect(service.activeTaskCount(for: project) == 0)
    }
}
