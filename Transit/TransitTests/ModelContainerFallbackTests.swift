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

    @Test("Failed container creation falls back to in-memory container")
    func fallbackOnFailure() {
        // Use an invalid store URL to force a ModelContainer init failure.
        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self])
        let bogusURL = URL(fileURLWithPath: "/dev/null/impossible/store.sqlite")
        let config = ModelConfiguration(
            schema: schema,
            url: bogusURL,
            cloudKitDatabase: .none
        )
        let result = ContainerFactory.makeContainer(schema: schema, configuration: config)

        // The container should still be usable (in-memory fallback).
        #expect(result.container.mainContext != nil)
        // An error should be reported so the UI can inform the user.
        #expect(result.error != nil)
    }

    @Test("Fallback container is functional for basic operations")
    func fallbackContainerIsUsable() throws {
        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self])
        let bogusURL = URL(fileURLWithPath: "/dev/null/impossible/store.sqlite")
        let config = ModelConfiguration(
            schema: schema,
            url: bogusURL,
            cloudKitDatabase: .none
        )
        let result = ContainerFactory.makeContainer(schema: schema, configuration: config)

        // Verify the fallback container can actually store and retrieve data.
        let context = result.container.mainContext
        let project = Project(name: "Test", description: nil, gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        try context.save()

        let descriptor = FetchDescriptor<Project>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Test")
    }
}
