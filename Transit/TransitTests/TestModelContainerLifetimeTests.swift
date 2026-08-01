import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TestModelContainerLifetimeTests {
    private final class WeakContainerReference {
        weak var value: ModelContainer?
    }

    private func makeEscapedContext() throws -> (ModelContext, WeakContainerReference) {
        let fixture = try TestModelContainer()
        let containerReference = WeakContainerReference()
        containerReference.value = fixture.container
        return (fixture.context, containerReference)
    }

    @Test func escapedContextKeepsBackingContainerAvailableForItsFullUse() throws {
        let (context, containerReference) = try makeEscapedContext()

        #expect(containerReference.value != nil)

        let project = Project(
            name: "Lifetime probe",
            description: "",
            gitRepo: nil,
            colorHex: "#000000"
        )
        context.insert(project)
        try context.save()

        let retainedContainer = try #require(containerReference.value)
        let verificationContext = ModelContext(retainedContainer)
        let persistedProjects = try verificationContext.fetch(FetchDescriptor<Project>())

        #expect(persistedProjects.contains { $0.name == "Lifetime probe" })
        #expect(containerReference.value != nil)
    }
}
