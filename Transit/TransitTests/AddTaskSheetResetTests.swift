import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-825: On macOS, opening "New Task" after saving one
/// must show an empty form, not the previously entered values.
///
/// Root cause: `Window("New Task", id: "add-task")` is a singleton scene whose
/// view is reused across opens, so `@State` persists between sessions. The fix
/// resets the form fields on macOS when the view appears.
///
/// These tests cover the pure helpers that the view delegates to for reset
/// behaviour, so the contract is exercised independently of SwiftUI rendering.
@MainActor @Suite(.serialized)
struct AddTaskSheetResetTests {

    // MARK: - Defaults

    @Test("Default form values are empty / .feature / no milestone")
    func defaultValuesAreEmpty() {
        let defaults = AddTaskFormResetLogic.defaults
        #expect(defaults.name.isEmpty)
        #expect(defaults.description.isEmpty)
        #expect(defaults.type == .feature)
        #expect(defaults.priority == .medium)
        #expect(defaults.milestone == nil)
    }

    // MARK: - Default project selection

    @Test("Default project picks the first project when none selected")
    func defaultProjectPicksFirstWhenNil() throws {
        let context = try TestModelContainer.newContext()
        let alpha = makeProject(name: "Alpha", in: context)
        let beta = makeProject(name: "Beta", in: context)
        let projects = [alpha, beta]

        let result = AddTaskFormResetLogic.defaultProjectID(from: projects, current: nil)
        #expect(result == alpha.id)
    }

    @Test("Default project keeps current selection when it still exists")
    func defaultProjectKeepsCurrentWhenValid() throws {
        let context = try TestModelContainer.newContext()
        let alpha = makeProject(name: "Alpha", in: context)
        let beta = makeProject(name: "Beta", in: context)
        let projects = [alpha, beta]

        let result = AddTaskFormResetLogic.defaultProjectID(from: projects, current: beta.id)
        #expect(result == beta.id)
    }

    @Test("Default project falls back to first when current project no longer exists")
    func defaultProjectFallsBackWhenCurrentMissing() throws {
        let context = try TestModelContainer.newContext()
        let alpha = makeProject(name: "Alpha", in: context)
        let projects = [alpha]

        let staleID = UUID()
        let result = AddTaskFormResetLogic.defaultProjectID(from: projects, current: staleID)
        #expect(result == alpha.id)
    }

    @Test("Default project returns nil when there are no projects")
    func defaultProjectReturnsNilWhenNoProjects() {
        let result = AddTaskFormResetLogic.defaultProjectID(from: [], current: nil)
        #expect(result == nil)
    }

    // MARK: - Helpers

    private func makeProject(name: String, in context: ModelContext) -> Project {
        let project = Project(
            name: name,
            description: "",
            gitRepo: nil,
            colorHex: "#FF0000"
        )
        context.insert(project)
        return project
    }
}
