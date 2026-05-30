import Foundation
import Testing
@testable import Transit

// MARK: - ReportMilestone taskCountLabel Tests
//
// Regression tests for T-879: ReportView pluralized one-task milestones as
// "1 tasks". The pluralization now lives in `ReportMilestone.taskCountLabel`,
// shared by both the SwiftUI ReportView and the markdown formatter.

@MainActor
@Suite("ReportMilestone taskCountLabel")
struct ReportMilestoneTaskCountLabelTests {

    private func makeMilestone(taskCount: Int) -> ReportMilestone {
        ReportMilestone(
            id: UUID(), displayID: "M-1", name: "Sample",
            isAbandoned: false, taskCount: taskCount
        )
    }

    @Test("Single task uses singular form")
    func singularForm() {
        // Expected: "1 task" — actual bug rendered "1 tasks"
        #expect(makeMilestone(taskCount: 1).taskCountLabel == "1 task")
    }

    @Test("Zero tasks uses plural form")
    func zeroTasks() {
        #expect(makeMilestone(taskCount: 0).taskCountLabel == "0 tasks")
    }

    @Test("Multiple tasks uses plural form")
    func multipleTasks() {
        #expect(makeMilestone(taskCount: 3).taskCountLabel == "3 tasks")
    }
}
