import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor
@Suite(.serialized)
struct ModelContainerFallbackTests {

    @Test("Successful container creation returns no error")
    func successfulCreation() {
        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let result = ContainerFactory.makeContainer(schema: schema, configuration: config)
        #expect(result.error == nil)
    }

    /// Forces the primary container creation to throw so the fallback path is
    /// exercised deterministically, independent of SwiftData's lazy store-open
    /// behavior (a bogus store URL no longer fails at init).
    private enum InjectedFailure: Error { case primaryCreationFailed }

    @Test("Failed container creation falls back to in-memory container")
    func fallbackOnFailure() {
        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let result = ContainerFactory.makeContainer(schema: schema, configuration: config) { _, _ in
            throw InjectedFailure.primaryCreationFailed
        }

        // An error should be reported so the UI can inform the user.
        #expect(result.error != nil)
    }

    @Test("Fallback container is functional for basic operations")
    func fallbackContainerIsUsable() throws {
        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let result = ContainerFactory.makeContainer(schema: schema, configuration: config) { _, _ in
            throw InjectedFailure.primaryCreationFailed
        }

        // Verify the fallback container can actually store and retrieve data.
        let context = result.container.mainContext
        let project = Project(name: "Test", description: "", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        try context.save()

        let descriptor = FetchDescriptor<Project>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Test")
    }
}
