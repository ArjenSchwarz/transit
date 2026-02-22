import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct ProjectEntityTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Project.self, TransitTask.self, Milestone.self])
        let config = ModelConfiguration(
            "ProjectEntityTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test func fromProjectMapsFields() throws {
        let context = try makeContext()
        let project = Project(name: "Alpha", description: "desc", gitRepo: nil, colorHex: "#112233")
        context.insert(project)

        let entity = ProjectEntity.from(project)
        #expect(entity.id == project.id.uuidString)
        #expect(entity.projectId == project.id)
        #expect(entity.name == "Alpha")
    }

    @Test func entitiesForIdentifiersReturnsMatchesOnly() throws {
        let context = try makeContext()
        let alpha = Project(name: "Alpha", description: "desc", gitRepo: nil, colorHex: "#111111")
        let beta = Project(name: "Beta", description: "desc", gitRepo: nil, colorHex: "#222222")
        context.insert(alpha)
        context.insert(beta)

        let entities = ProjectEntityQuery.entities(
            for: [alpha.id.uuidString, UUID().uuidString, "not-a-uuid"],
            modelContext: context
        )

        #expect(entities.count == 1)
        #expect(entities.first?.projectId == alpha.id)
    }

    @Test func suggestedEntitiesReturnsEmptyArrayWhenNoProjects() throws {
        let context = try makeContext()
        let entities = ProjectEntityQuery.suggestedEntities(modelContext: context)
        #expect(entities.isEmpty)
    }
}
