import Foundation
import SwiftData
import Testing
@testable import Transit

/// Contract tests for the `ModelContext` save helpers (T-344).
///
/// The point of these tests is the *difference* between the two helpers:
/// `saveOrRollback` reverts the whole context, `insertOrDelete` removes only the
/// model it inserted. Collapsing the two would reintroduce T-452/T-486, so the
/// recovery strategy is asserted directly rather than inferred from callers.
@MainActor @Suite(.serialized)
struct ModelContextSaveHelpersTests {

    // MARK: - Helpers

    /// A project already committed to the store, so rollback has a persisted
    /// value to restore.
    private func makePersistedProject(in context: ModelContext, name: String = "Original") throws -> Project {
        let project = Project(name: name, description: "Desc", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        try context.save()
        return project
    }

    // MARK: - saveOrRollback

    @Test func saveOrRollbackPersistsMutation() throws {
        let context = try TestModelContainer.newContext()
        let project = try makePersistedProject(in: context)

        try context.saveOrRollback { project.name = "Renamed" }

        context.safeRollback()
        #expect(project.name == "Renamed")
    }

    @Test func saveOrRollbackRevertsContextWhenMutationThrows() throws {
        let context = try TestModelContainer.newContext()
        let project = try makePersistedProject(in: context)

        #expect(throws: SaveFailure.self) {
            try context.saveOrRollback {
                project.name = "Renamed"
                throw SaveFailure.simulated
            }
        }

        #expect(project.name == "Original")
    }

    @Test func saveOrRollbackWithSaveFalseAppliesMutationWithoutPersisting() throws {
        let context = try TestModelContainer.newContext()
        let project = try makePersistedProject(in: context)

        try context.saveOrRollback(save: false) { project.name = "Renamed" }
        #expect(project.name == "Renamed")

        // Never persisted, so a rollback discards it.
        context.safeRollback()
        #expect(project.name == "Original")
    }

    @Test func saveOrRollbackWithSaveFalseStillRevertsWhenMutationThrows() throws {
        let context = try TestModelContainer.newContext()
        let project = try makePersistedProject(in: context)

        #expect(throws: SaveFailure.self) {
            try context.saveOrRollback(save: false) {
                project.name = "Renamed"
                throw SaveFailure.simulated
            }
        }

        #expect(project.name == "Original")
    }

    // MARK: - insertOrDelete

    @Test func insertOrDeletePersistsModelOnSuccess() throws {
        let context = try TestModelContainer.newContext()
        let project = try makePersistedProject(in: context)
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .permanent(1))

        try context.insertOrDelete(task)

        context.safeRollback()
        #expect(try context.fetch(FetchDescriptor<TransitTask>()).count == 1)
    }

    @Test func insertOrDeleteRemovesInsertedModelOnSaveFailure() throws {
        let context = try TestModelContainer.newContext()
        let project = try makePersistedProject(in: context)
        let task = TransitTask(name: "Ghost", type: .feature, project: project, displayID: .permanent(1))

        #expect(throws: SaveFailure.self) {
            try context.insertOrDelete(task, save: { _ in throw SaveFailure.simulated })
        }

        // The insert must not survive to be committed by a later, unrelated save
        // (T-486).
        try context.save()
        #expect(try context.fetch(FetchDescriptor<TransitTask>()).isEmpty)
    }

    /// The distinction that must never be lost: creation recovers by deleting the
    /// inserted model, *not* by rolling the context back. A rollback here would
    /// also discard the user's unrelated unsaved edits on the shared main context.
    @Test func insertOrDeleteFailurePreservesUnrelatedUnsavedEdits() throws {
        let context = try TestModelContainer.newContext()
        let project = try makePersistedProject(in: context)
        let task = TransitTask(name: "Ghost", type: .feature, project: project, displayID: .permanent(1))

        project.name = "Unsaved edit"

        #expect(throws: SaveFailure.self) {
            try context.insertOrDelete(task, save: { _ in throw SaveFailure.simulated })
        }

        #expect(project.name == "Unsaved edit")
    }
}
