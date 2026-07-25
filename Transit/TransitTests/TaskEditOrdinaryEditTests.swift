import Foundation
import SwiftData
import Testing
@testable import Transit

// MARK: - Ordinary editing

/// The merge must not get in the way when there is no external writer.
@MainActor @Suite(.serialized)
struct TaskEditOrdinaryEditTests {

    /// With nothing else writing, every user edit is applied as before.
    @Test func userEditsApplyWhenNothingElseChanged() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
        let baseline = TaskEditSnapshot(task: task)

        let milestone = try await env.milestoneService.createMilestone(
            name: "Launch",
            description: nil,
            project: env.project
        )

        var edited = baseline
        edited.name = "New name"
        edited.description = "New description"
        edited.type = .research
        edited.priority = .high
        edited.status = .inProgress
        edited.metadata = ["key": "value"]
        edited.milestoneID = milestone.id

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))
        #expect(merge.hasConflicts == false)

        try env.apply(merge, edited: edited, to: task, milestone: milestone)

        #expect(task.name == "New name")
        #expect(task.taskDescription == "New description")
        #expect(task.type == .research)
        #expect(task.priority == .high)
        #expect(task.status == .inProgress)
        #expect(task.metadata == ["key": "value"])
        #expect(task.milestone?.id == milestone.id)
    }

    /// T-854: emptying the description field must still clear a stored
    /// description rather than reading as "no change requested".
    @Test func emptyingDescriptionStillClearsIt() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
        let baseline = TaskEditSnapshot(task: task)

        var edited = baseline
        edited.description = ""

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))
        #expect(merge.changedFields == [.description])

        try env.apply(merge, edited: edited, to: task)

        #expect(task.taskDescription == nil)
    }

    /// A user-initiated project move still clears the milestone (Decision 6).
    @Test func changingProjectClearsMilestone() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
        let milestone = try await env.milestoneService.createMilestone(
            name: "Launch",
            description: nil,
            project: env.project
        )
        try env.milestoneService.setMilestone(milestone, on: task)

        let otherProject = Project(name: "Other", description: "", gitRepo: nil, colorHex: "#00FF00")
        env.context.insert(otherProject)

        let baseline = TaskEditSnapshot(task: task)
        var edited = baseline
        edited.projectID = otherProject.id
        edited.milestoneID = nil

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))
        #expect(merge.changedFields == [.project, .milestone])

        try env.apply(merge, edited: edited, to: task, project: otherProject, milestone: nil)

        #expect(task.project?.id == otherProject.id)
        #expect(task.milestone == nil)
    }
}
