//
//  ProjectServiceTests.swift
//  TransitTests
//
//  Tests for ProjectService.
//

import SwiftData
import SwiftUI
import Testing
@testable import Transit

@MainActor
struct ProjectServiceTests {
    private func makeTestContext() -> ModelContext {
        let schema = Schema([Project.self, TransitTask.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            fatalError("Failed to create test container")
        }
        return ModelContext(container)
    }

    @Test func createProject() throws {
        let context = makeTestContext()
        let service = ProjectService(modelContext: context)

        let project = try service.createProject(
            name: "Test Project",
            description: "A test project",
            gitRepo: "https://github.com/test/repo",
            color: .blue
        )

        #expect(project.name == "Test Project")
        #expect(project.projectDescription == "A test project")
        #expect(project.gitRepo == "https://github.com/test/repo")
        #expect(project.colorHex.hasPrefix("#"))
    }

    @Test func findProjectByID() throws {
        let context = makeTestContext()
        let service = ProjectService(modelContext: context)

        let created = try service.createProject(
            name: "Find Me",
            description: "Test",
            gitRepo: nil,
            color: .red
        )

        let found = try service.findProject(id: created.id)
        #expect(found?.id == created.id)
        #expect(found?.name == "Find Me")
    }

    @Test func findProjectByIDNotFound() throws {
        let context = makeTestContext()
        let service = ProjectService(modelContext: context)

        let found = try service.findProject(id: UUID())
        #expect(found == nil)
    }

    @Test func findProjectByName() throws {
        let context = makeTestContext()
        let service = ProjectService(modelContext: context)

        _ = try service.createProject(
            name: "Unique Name",
            description: "Test",
            gitRepo: nil,
            color: .green
        )

        let found = try service.findProject(name: "Unique Name")
        #expect(found?.name == "Unique Name")
    }

    @Test func findProjectByNameCaseInsensitive() throws {
        let context = makeTestContext()
        let service = ProjectService(modelContext: context)

        _ = try service.createProject(
            name: "MyProject",
            description: "Test",
            gitRepo: nil,
            color: .orange
        )

        let found = try service.findProject(name: "myproject")
        #expect(found?.name == "MyProject")
    }

    @Test func findProjectByNameTrimsWhitespace() throws {
        let context = makeTestContext()
        let service = ProjectService(modelContext: context)

        _ = try service.createProject(
            name: "Trimmed",
            description: "Test",
            gitRepo: nil,
            color: .purple
        )

        let found = try service.findProject(name: "  Trimmed  ")
        #expect(found?.name == "Trimmed")
    }

    @Test func findProjectByNameNotFound() throws {
        let context = makeTestContext()
        let service = ProjectService(modelContext: context)

        let found = try service.findProject(name: "Nonexistent")
        #expect(found == nil)
    }

    @Test func findProjectByNameAmbiguous() throws {
        let context = makeTestContext()
        let service = ProjectService(modelContext: context)

        _ = try service.createProject(
            name: "Duplicate",
            description: "First",
            gitRepo: nil,
            color: .red
        )
        _ = try service.createProject(
            name: "Duplicate",
            description: "Second",
            gitRepo: nil,
            color: .blue
        )

        #expect(throws: ProjectServiceError.self) {
            _ = try service.findProject(name: "Duplicate")
        }
    }

    @Test func activeTaskCountWithNoTasks() throws {
        let context = makeTestContext()
        let service = ProjectService(modelContext: context)

        let project = try service.createProject(
            name: "Empty",
            description: "No tasks",
            gitRepo: nil,
            color: .gray
        )

        let count = service.activeTaskCount(for: project)
        #expect(count == 0)
    }

    @Test func activeTaskCountExcludesTerminalTasks() throws {
        let context = makeTestContext()
        let service = ProjectService(modelContext: context)

        let project = try service.createProject(
            name: "Mixed",
            description: "Mixed tasks",
            gitRepo: nil,
            color: .cyan
        )

        // Create tasks with different statuses
        let task1 = TransitTask(
            name: "Active",
            description: nil,
            type: .feature,
            project: project,
            permanentDisplayId: 1,
            metadata: nil
        )
        task1.status = .inProgress

        let task2 = TransitTask(
            name: "Done",
            description: nil,
            type: .feature,
            project: project,
            permanentDisplayId: 2,
            metadata: nil
        )
        task2.status = .done

        let task3 = TransitTask(
            name: "Abandoned",
            description: nil,
            type: .feature,
            project: project,
            permanentDisplayId: 3,
            metadata: nil
        )
        task3.status = .abandoned

        context.insert(task1)
        context.insert(task2)
        context.insert(task3)
        try context.save()

        let count = service.activeTaskCount(for: project)
        #expect(count == 1)  // Only task1 is active
    }
}
