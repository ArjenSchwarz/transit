import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MilestoneDisplayNameTests {

    private func makeContext() throws -> ModelContext {
        try TestModelContainer.newContext()
    }

    private func makeProject(in context: ModelContext, name: String) -> Project {
        let project = Project(name: name, description: nil, gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    // MARK: - displayName (T-223 regression)

    @Test("displayName includes project name when project exists")
    func displayNameWithProject() throws {
        let context = try makeContext()
        let project = makeProject(in: context, name: "Prism")
        let milestone = Milestone(name: "Beta 1", project: project, displayID: .permanent(1))
        context.insert(milestone)

        #expect(milestone.displayName == "Prism - Beta 1")
    }

    @Test("displayName falls back to milestone name when project is nil")
    func displayNameWithoutProject() throws {
        let context = try makeContext()
        let project = makeProject(in: context, name: "Temp")
        let milestone = Milestone(name: "Beta 1", project: project, displayID: .permanent(2))
        context.insert(milestone)
        milestone.project = nil

        #expect(milestone.displayName == "Beta 1")
    }
}
