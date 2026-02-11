import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor
@Suite(.serialized)
struct ProjectEntityQueryTests {

    // MARK: - Setup

    private func setupDependencies(context: ModelContext) -> ProjectService {
        let projectService = ProjectService(modelContext: context)
        AppDependencyManager.shared.add(dependency: projectService)
        return projectService
    }

    // MARK: - entities(for:)

    @Test func entitiesForIdentifiersReturnsMatchingProjects() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        let project1 = projectService.createProject(name: "Alpha", description: "First", gitRepo: nil, colorHex: "#FF0000")
        let project2 = projectService.createProject(name: "Beta", description: "Second", gitRepo: nil, colorHex: "#00FF00")
        let project3 = projectService.createProject(name: "Gamma", description: "Third", gitRepo: nil, colorHex: "#0000FF")

        let query = ProjectEntityQuery()
        let identifiers = [project1.id.uuidString, project3.id.uuidString]
        let entities = try await query.entities(for: identifiers)

        #expect(entities.count == 2)
        #expect(entities.contains { $0.projectId == project1.id })
        #expect(entities.contains { $0.projectId == project3.id })
        #expect(!entities.contains { $0.projectId == project2.id })
    }

    @Test func entitiesForIdentifiersReturnsEmptyArrayWhenNoMatches() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        projectService.createProject(name: "Alpha", description: "First", gitRepo: nil, colorHex: "#FF0000")

        let query = ProjectEntityQuery()
        let nonExistentId = UUID().uuidString
        let entities = try await query.entities(for: [nonExistentId])

        #expect(entities.isEmpty)
    }

    @Test func entitiesForIdentifiersHandlesEmptyIdentifierList() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        projectService.createProject(name: "Alpha", description: "First", gitRepo: nil, colorHex: "#FF0000")

        let query = ProjectEntityQuery()
        let entities = try await query.entities(for: [])

        #expect(entities.isEmpty)
    }

    @Test func entitiesForIdentifiersIgnoresInvalidUUIDs() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        let project = projectService.createProject(name: "Alpha", description: "First", gitRepo: nil, colorHex: "#FF0000")

        let query = ProjectEntityQuery()
        let identifiers = [project.id.uuidString, "not-a-uuid", "also-invalid"]
        let entities = try await query.entities(for: identifiers)

        #expect(entities.count == 1)
        #expect(entities[0].projectId == project.id)
    }

    @Test func entitiesForIdentifiersHandlesDuplicateIdentifiers() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        let project = projectService.createProject(name: "Alpha", description: "First", gitRepo: nil, colorHex: "#FF0000")

        let query = ProjectEntityQuery()
        let identifiers = [project.id.uuidString, project.id.uuidString]
        let entities = try await query.entities(for: identifiers)

        // Should return the project once, not duplicated
        #expect(entities.count == 1)
        #expect(entities[0].projectId == project.id)
    }

    // MARK: - suggestedEntities()

    @Test func suggestedEntitiesReturnsAllProjects() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        let project1 = projectService.createProject(name: "Alpha", description: "First", gitRepo: nil, colorHex: "#FF0000")
        let project2 = projectService.createProject(name: "Beta", description: "Second", gitRepo: nil, colorHex: "#00FF00")
        let project3 = projectService.createProject(name: "Gamma", description: "Third", gitRepo: nil, colorHex: "#0000FF")

        let query = ProjectEntityQuery()
        let entities = try await query.suggestedEntities()

        #expect(entities.count == 3)
        #expect(entities.contains { $0.projectId == project1.id })
        #expect(entities.contains { $0.projectId == project2.id })
        #expect(entities.contains { $0.projectId == project3.id })
    }

    @Test func suggestedEntitiesReturnsEmptyArrayWhenNoProjects() async throws {
        let context = try TestModelContainer.newContext()
        _ = setupDependencies(context: context)

        let query = ProjectEntityQuery()
        let entities = try await query.suggestedEntities()

        #expect(entities.isEmpty)
    }

    @Test func suggestedEntitiesPreservesProjectProperties() async throws {
        let context = try TestModelContainer.newContext()
        let projectService = setupDependencies(context: context)

        let project = projectService.createProject(name: "Test Project", description: "Description", gitRepo: "https://github.com/test/repo", colorHex: "#FF5733")

        let query = ProjectEntityQuery()
        let entities = try await query.suggestedEntities()

        #expect(entities.count == 1)
        let entity = entities[0]
        #expect(entity.projectId == project.id)
        #expect(entity.name == "Test Project")
        #expect(entity.id == project.id.uuidString)
    }
}
