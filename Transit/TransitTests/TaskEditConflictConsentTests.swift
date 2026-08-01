import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for the T-1935 consent scoping in `EditMerge`.
///
/// `TaskEditConcurrentUpdateTests` covers the cases where a changed conflict
/// snapshot *revokes* the user's answer. These cover the other half: an answer
/// that is still valid must survive, otherwise a conflict alert could never be
/// dismissed and no save behind one could ever complete.
@MainActor @Suite(.serialized)
struct TaskEditConflictConsentTests {

    /// An unchanged conflict still matches, and an external write to a field the
    /// user never touched does not revoke the answer. Without this, always
    /// returning `false` would look correct while making every conflict alert
    /// impossible to get past.
    @Test func unchangedConflictSnapshotKeepsAlertConsent() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
        let baseline = TaskEditSnapshot(task: task)

        var edited = baseline
        edited.name = "Renamed by the user"

        try env.taskService.updateTask(task, name: "Renamed by MCP")
        let shown = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))
        #expect(shown.conflictingFields == [.name])
        #expect(shown.hasSameConflictSnapshot(as: shown))

        // An untouched field changing externally is not part of the conflict the
        // user answered, so it must not invalidate their choice.
        try env.taskService.updateTask(task, description: "Rewritten by MCP")
        let current = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))

        #expect(current.conflictingFields == [.name])
        #expect(current.hasSameConflictSnapshot(as: shown))
    }

    /// A conflict-free merge trivially matches itself, so "Use Updated Values"
    /// on an already-resolved merge rebases instead of re-alerting forever.
    @Test func conflictFreeMergeMatchesItself() async throws {
        let env = try TaskEditTestEnv.make()
        let task = try await env.makeTask()
        let baseline = TaskEditSnapshot(task: task)

        var edited = baseline
        edited.priority = .high

        let merge = TaskEditMerge(original: baseline, edited: edited, live: TaskEditSnapshot(task: task))

        #expect(merge.hasConflicts == false)
        #expect(merge.hasSameConflictSnapshot(as: merge))
    }
}
