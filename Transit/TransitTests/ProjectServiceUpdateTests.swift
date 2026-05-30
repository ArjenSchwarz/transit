import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1397: editing an existing project must enforce the
/// same name invariants as creation. Previously `ProjectEditView.save()` mutated
/// `project.name` directly with only a duplicate check, so an empty or
/// whitespace-only name could be persisted. The invariant now lives in
/// `ProjectService.updateProject(...)`.
@MainActor @Suite(.serialized)
struct ProjectServiceUpdateTests {

    // MARK: - Helpers

    private func makeService() throws -> (ProjectService, ModelContext) {
        let context = try TestModelContainer.newContext()
        let service = ProjectService(modelContext: context)
        return (service, context)
    }

    // MARK: - Empty name prevention

    @Test func updateProjectWithEmptyNameThrowsInvalidName() throws {
        let (service, _) = try makeService()
        let project = try service.createProject(name: "Transit", description: "Desc", gitRepo: nil, colorHex: "#000000")

        #expect {
            try service.updateProject(project, name: "", description: "Desc", gitRepo: nil, colorHex: "#000000")
        } throws: { error in
            if case .invalidName = error as? ProjectMutationError { return true }
            return false
        }
        // The original name must be preserved when the rename is rejected.
        #expect(project.name == "Transit")
    }

    @Test func updateProjectWithWhitespaceOnlyNameThrowsInvalidName() throws {
        let (service, _) = try makeService()
        let project = try service.createProject(name: "Transit", description: "Desc", gitRepo: nil, colorHex: "#000000")

        #expect {
            try service.updateProject(project, name: "   ", description: "Desc", gitRepo: nil, colorHex: "#000000")
        } throws: { error in
            if case .invalidName = error as? ProjectMutationError { return true }
            return false
        }
        #expect(project.name == "Transit")
    }

    @Test func updateProjectWithNewlinesOnlyNameThrowsInvalidName() throws {
        let (service, _) = try makeService()
        let project = try service.createProject(name: "Transit", description: "Desc", gitRepo: nil, colorHex: "#000000")

        #expect {
            try service.updateProject(project, name: "\n\t\n", description: "Desc", gitRepo: nil, colorHex: "#000000")
        } throws: { error in
            if case .invalidName = error as? ProjectMutationError { return true }
            return false
        }
        #expect(project.name == "Transit")
    }

    // MARK: - Duplicate name prevention

    @Test func updateProjectWithDuplicateNameThrows() throws {
        let (service, _) = try makeService()
        try service.createProject(name: "Transit", description: "First", gitRepo: nil, colorHex: "#000000")
        let orbit = try service.createProject(name: "Orbit", description: "Second", gitRepo: nil, colorHex: "#111111")

        #expect {
            try service.updateProject(orbit, name: "Transit", description: "Second", gitRepo: nil, colorHex: "#111111")
        } throws: { error in
            if case .duplicateName = error as? ProjectMutationError { return true }
            return false
        }
        #expect(orbit.name == "Orbit")
    }

    @Test func updateProjectWithCaseFoldedDuplicateNameThrows() throws {
        let (service, _) = try makeService()
        try service.createProject(name: "Transit", description: "First", gitRepo: nil, colorHex: "#000000")
        let orbit = try service.createProject(name: "Orbit", description: "Second", gitRepo: nil, colorHex: "#111111")

        // A different project's name must conflict case-insensitively.
        #expect {
            try service.updateProject(orbit, name: "transit", description: "Second", gitRepo: nil, colorHex: "#111111")
        } throws: { error in
            if case .duplicateName = error as? ProjectMutationError { return true }
            return false
        }
        #expect(orbit.name == "Orbit")
    }

    @Test func updateProjectAllowsRenamingToSameNameCaseVariant() throws {
        let (service, _) = try makeService()
        let project = try service.createProject(name: "Transit", description: "Desc", gitRepo: nil, colorHex: "#000000")

        // Renaming to a case variant of the project's own name must not conflict.
        try service.updateProject(project, name: "transit", description: "Desc", gitRepo: nil, colorHex: "#000000")
        #expect(project.name == "transit")
    }

    // MARK: - Successful update

    @Test func updateProjectUpdatesAllFieldsAndTrimsName() throws {
        let (service, context) = try makeService()
        let project = try service.createProject(name: "Transit", description: "Old", gitRepo: nil, colorHex: "#000000")

        try service.updateProject(
            project,
            name: "  Renamed  ",
            description: "New description",
            gitRepo: "https://github.com/user/repo",
            colorHex: "#FF5500"
        )

        #expect(project.name == "Renamed")
        #expect(project.projectDescription == "New description")
        #expect(project.gitRepo == "https://github.com/user/repo")
        #expect(project.colorHex == "#FF5500")
        // Changes were committed.
        #expect(context.hasChanges == false)
    }
}
