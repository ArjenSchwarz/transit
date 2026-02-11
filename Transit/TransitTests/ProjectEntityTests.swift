import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor
struct ProjectEntityTests {

    // MARK: - Initialization

    @Test func initializesWithAllProperties() {
        let id = UUID()
        let entity = ProjectEntity(
            id: id.uuidString,
            projectId: id,
            name: "Test Project"
        )

        #expect(entity.id == id.uuidString)
        #expect(entity.projectId == id)
        #expect(entity.name == "Test Project")
    }

    // MARK: - Display Representation

    @Test func displayRepresentationIsCreated() {
        let entity = ProjectEntity(
            id: UUID().uuidString,
            projectId: UUID(),
            name: "My Project"
        )

        // Just verify the display representation can be accessed
        let _ = entity.displayRepresentation
    }

    @Test func typeDisplayRepresentationIsCreated() {
        // Just verify the type display representation can be accessed
        let _ = ProjectEntity.typeDisplayRepresentation
    }

    // MARK: - Factory Method

    @Test func fromProjectCreatesEntityWithCorrectProperties() throws {
        let context = try TestModelContainer.newContext()
        let project = Project(name: "Alpha", description: "Test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)

        let entity = ProjectEntity.from(project)

        #expect(entity.id == project.id.uuidString)
        #expect(entity.projectId == project.id)
        #expect(entity.name == "Alpha")
    }

    @Test func fromProjectPreservesUUID() throws {
        let context = try TestModelContainer.newContext()
        let project = Project(name: "Beta", description: "Another test", gitRepo: nil, colorHex: "#00FF00")
        context.insert(project)

        let entity = ProjectEntity.from(project)

        #expect(entity.projectId == project.id)
        #expect(UUID(uuidString: entity.id) == project.id)
    }

    // MARK: - Default Query

    @Test func defaultQueryReturnsProjectEntityQuery() {
        let query = ProjectEntity.defaultQuery
        #expect(type(of: query) == ProjectEntityQuery.self)
    }

    // MARK: - Edge Cases

    @Test func handlesEmptyProjectName() {
        let entity = ProjectEntity(
            id: UUID().uuidString,
            projectId: UUID(),
            name: ""
        )

        #expect(entity.name == "")
    }

    @Test func handlesProjectNameWithSpecialCharacters() {
        let entity = ProjectEntity(
            id: UUID().uuidString,
            projectId: UUID(),
            name: "Project #1 (Test) & \"Demo\""
        )

        #expect(entity.name == "Project #1 (Test) & \"Demo\"")
    }

    @Test func handlesProjectNameWithUnicode() {
        let entity = ProjectEntity(
            id: UUID().uuidString,
            projectId: UUID(),
            name: "🚀 Rocket Project"
        )

        #expect(entity.name == "🚀 Rocket Project")
    }
}
