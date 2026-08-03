import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct ProjectEntityTests {
    @MainActor
    private struct TestEnv {
        let testContainer: TestModelContainer
        let projectService: ProjectService

        var context: ModelContext { testContainer.context }
    }

    private func makeEnv() throws -> TestEnv {
        let testContainer = try TestModelContainer()
        return TestEnv(
            testContainer: testContainer,
            projectService: ProjectService(modelContext: testContainer.context)
        )
    }

    @Test func fromProjectMapsFields() throws {
        let env = try makeEnv()
        let project = Project(name: "Alpha", description: "desc", gitRepo: nil, colorHex: "#112233")
        env.context.insert(project)

        let entity = ProjectEntity.from(project)
        #expect(entity.id == project.id.uuidString)
        #expect(entity.projectId == project.id)
        #expect(entity.name == "Alpha")
    }

    @Test func entitiesForIdentifiersReturnsMatchesOnly() throws {
        let env = try makeEnv()
        let alpha = Project(name: "Alpha", description: "desc", gitRepo: nil, colorHex: "#111111")
        let beta = Project(name: "Beta", description: "desc", gitRepo: nil, colorHex: "#222222")
        env.context.insert(alpha)
        env.context.insert(beta)

        let entities = try ProjectEntityQuery.entities(
            for: [alpha.id.uuidString, UUID().uuidString, "not-a-uuid"],
            projectService: env.projectService
        )

        #expect(entities.count == 1)
        #expect(entities.first?.projectId == alpha.id)
    }

    @Test func suggestedEntitiesReturnsEmptyArrayWhenNoProjects() throws {
        let env = try makeEnv()
        let entities = try ProjectEntityQuery.suggestedEntities(projectService: env.projectService)
        #expect(entities.isEmpty)
    }
}
