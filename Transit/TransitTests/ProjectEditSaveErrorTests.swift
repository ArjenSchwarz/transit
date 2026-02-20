import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-154: ProjectEditView must not silently discard save
/// failures when editing an existing project.
///
/// The fix ensures save() uses do/catch instead of try?, surfaces errors via an
/// alert, and rolls back the model context on failure so in-memory state is not
/// left inconsistent.
@MainActor @Suite(.serialized)
struct ProjectEditSaveErrorTests {

    // MARK: - Helpers

    private func makeContext() throws -> ModelContext {
        try TestModelContainer.newContext()
    }

    private func makeProject(
        name: String = "Test Project",
        in context: ModelContext
    ) -> Project {
        let project = Project(
            name: name,
            description: "A test project",
            gitRepo: "https://github.com/example/repo",
            colorHex: "#FF0000"
        )
        context.insert(project)
        return project
    }

    // MARK: - Rollback restores project properties after failed save

    @Test func rollbackRevertsNameChangeOnProject() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        try context.save()

        // Simulate what ProjectEditView.save() does: mutate properties directly
        project.name = "Renamed Project"
        #expect(project.name == "Renamed Project")

        // Rollback should revert to the last persisted state
        context.rollback()
        #expect(project.name == "Test Project")
    }

    @Test func rollbackRevertsDescriptionChangeOnProject() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        try context.save()

        project.projectDescription = "Updated description"
        #expect(project.projectDescription == "Updated description")

        context.rollback()
        #expect(project.projectDescription == "A test project")
    }

    @Test func rollbackRevertsAllPropertyChangesOnProject() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        try context.save()

        // Mutate all editable properties (as ProjectEditView.save() does)
        project.name = "New Name"
        project.projectDescription = "New description"
        project.gitRepo = "https://github.com/other/repo"
        project.colorHex = "#00FF00"

        #expect(project.name == "New Name")
        #expect(project.projectDescription == "New description")
        #expect(project.gitRepo == "https://github.com/other/repo")
        #expect(project.colorHex == "#00FF00")

        context.rollback()

        #expect(project.name == "Test Project")
        #expect(project.projectDescription == "A test project")
        #expect(project.gitRepo == "https://github.com/example/repo")
        #expect(project.colorHex == "#FF0000")
    }

    @Test func rollbackRevertsGitRepoRemoval() throws {
        let context = try makeContext()
        let project = makeProject(in: context)
        try context.save()

        // Simulate clearing the git repo field (empty string -> nil)
        project.gitRepo = nil
        #expect(project.gitRepo == nil)

        context.rollback()
        #expect(project.gitRepo == "https://github.com/example/repo")
    }
}
