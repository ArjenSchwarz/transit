import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TestModelContainerLifetimeTests {
    @Test func fixtureRetainsBackingContainerForItsFullUse() throws {
        let fixture = try TestModelContainer()
        let context = fixture.context
        weak var container = fixture.container

        #expect(container != nil)

        let project = Project(
            name: "Lifetime probe",
            description: "",
            gitRepo: nil,
            colorHex: "#000000"
        )
        context.insert(project)

        #expect(project.name == "Lifetime probe")
        #expect(container != nil)
        withExtendedLifetime(fixture) {}
    }
}
