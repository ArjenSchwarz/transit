import Foundation
import SwiftData
import Testing
@testable import Transit

/// T-2018 regressions for a task-edit project UUID whose model disappeared
/// from the editor's observed project list before Save.
@MainActor @Suite(.serialized)
struct TaskEditProjectResolutionTests {

    @Test func changedProjectWithoutResolvedModelFailsWithoutSavingAnyEdits() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
        let baseline = TaskEditSnapshot(task: task)

        var edited = baseline
        edited.name = "Edit that must not persist"
        edited.projectID = UUID()
        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))

        #expect(merge.changedFields == [.name, .project])
        #expect(throws: TaskEditApplier.Error.projectNotResolved) {
            try env.context.saveOrRollback {
                try env.apply(merge, edited: edited, to: task, project: nil)
            }
        }

        #expect(task.name == baseline.name)
        #expect(task.project?.id == env.project.id)
        #expect(task.milestone == nil)
    }

    @Test func changedProjectWithMismatchedModelFailsWithoutSavingAnyEdits() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
        let selectedProject = Project(name: "Selected", description: "", gitRepo: nil, colorHex: "#00FF00")
        let wrongProject = Project(name: "Wrong", description: "", gitRepo: nil, colorHex: "#0000FF")
        env.context.insert(selectedProject)
        env.context.insert(wrongProject)
        try env.context.save()

        let baseline = TaskEditSnapshot(task: task)
        var edited = baseline
        edited.name = "Edit that must not persist"
        edited.projectID = selectedProject.id
        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))

        #expect(merge.changedFields == [.name, .project])
        #expect(throws: TaskEditApplier.Error.projectNotResolved) {
            try env.context.saveOrRollback {
                try env.apply(merge, edited: edited, to: task, project: wrongProject)
            }
        }

        #expect(task.name == baseline.name)
        #expect(task.project?.id == env.project.id)
        #expect(task.milestone == nil)
    }

    @Test func vanishedProjectSelectionBlocksSaveAndSuppliesRetryableError() {
        let selection = UUID()
        let state = TaskEditProjectSelectionState(
            selectedProjectID: selection,
            resolvedProjectID: nil
        )

        #expect(state.isResolved == false)
        #expect(
            state.errorMessage == "The selected project is no longer available. Choose another project and try again."
        )
    }

    @Test func resolvedProjectSelectionCanSave() {
        let selection = UUID()
        let state = TaskEditProjectSelectionState(
            selectedProjectID: selection,
            resolvedProjectID: selection
        )

        #expect(state.isResolved)
    }

    @Test func unchangedProjectDoesNotRequireAResolvedModelParameter() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
        let baseline = TaskEditSnapshot(task: task)

        var edited = baseline
        edited.priority = .high
        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))

        try env.context.saveOrRollback {
            try env.apply(merge, edited: edited, to: task, project: nil)
        }

        #expect(task.priority == .high)
        #expect(task.project?.id == env.project.id)
    }
}
