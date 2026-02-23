import Foundation
import SwiftData
import Testing
@testable import Transit

// MARK: - ReportLogic Milestone Tests

@MainActor
@Suite(.serialized)
struct ReportMilestoneTests {

    // MARK: - Milestone Inclusion

    @Test("Completed milestones included in report grouped by project")
    func completedMilestonesIncluded() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Alpha", context: ctx)

        let milestone = Milestone(name: "v1.0", project: project, displayID: .permanent(1))
        ctx.insert(milestone)
        milestone.statusRawValue = MilestoneStatus.done.rawValue
        milestone.completionDate = now
        milestone.lastStatusChangeDate = now

        let task = makeTerminalTask(name: "Task1", project: project, completionDate: now, context: ctx)

        let report = ReportLogic.buildReport(
            tasks: [task], milestones: [milestone], dateRange: .thisYear, now: now
        )

        #expect(report.projectGroups.count == 1)
        #expect(report.projectGroups[0].milestones.count == 1)
        #expect(report.projectGroups[0].milestones[0].name == "v1.0")
        #expect(report.projectGroups[0].milestones[0].displayID == "M-1")
        #expect(report.projectGroups[0].milestones[0].isAbandoned == false)
    }

    @Test("Abandoned milestones marked as isAbandoned")
    func abandonedMilestonesMarked() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let milestone = Milestone(name: "Cancelled", project: project, displayID: .permanent(2))
        ctx.insert(milestone)
        milestone.statusRawValue = MilestoneStatus.abandoned.rawValue
        milestone.completionDate = now
        milestone.lastStatusChangeDate = now

        let task = makeTerminalTask(name: "Task1", project: project, completionDate: now, context: ctx)

        let report = ReportLogic.buildReport(
            tasks: [task], milestones: [milestone], dateRange: .thisYear, now: now
        )

        #expect(report.projectGroups[0].milestones[0].isAbandoned == true)
    }

    @Test("Open milestones excluded from report")
    func openMilestonesExcluded() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let milestone = Milestone(name: "Open One", project: project, displayID: .permanent(1))
        ctx.insert(milestone)
        // Status defaults to open, no completionDate

        let task = makeTerminalTask(name: "Task1", project: project, completionDate: now, context: ctx)

        let report = ReportLogic.buildReport(
            tasks: [task], milestones: [milestone], dateRange: .thisYear, now: now
        )

        #expect(report.projectGroups[0].milestones.isEmpty)
    }

    @Test("Milestones without completionDate fall back to lastStatusChangeDate")
    func milestonesWithoutCompletionDateFallBack() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let milestone = Milestone(name: "No Date", project: project, displayID: .permanent(1))
        ctx.insert(milestone)
        milestone.statusRawValue = MilestoneStatus.done.rawValue
        milestone.lastStatusChangeDate = now
        // completionDate left nil

        let task = makeTerminalTask(name: "Task1", project: project, completionDate: now, context: ctx)

        let report = ReportLogic.buildReport(
            tasks: [task], milestones: [milestone], dateRange: .thisYear, now: now
        )

        #expect(report.projectGroups[0].milestones.count == 1)
        #expect(report.projectGroups[0].milestones[0].name == "No Date")
    }

    @Test("Milestone with nil completionDate excluded when lastStatusChangeDate is out of range")
    func milestoneNilCompletionDateOutOfRangeExcluded() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let oldDate = Calendar.current.date(byAdding: .year, value: -2, to: now)!
        let milestone = Milestone(name: "Old", project: project, displayID: .permanent(1))
        ctx.insert(milestone)
        milestone.statusRawValue = MilestoneStatus.done.rawValue
        milestone.lastStatusChangeDate = oldDate
        // completionDate left nil

        let task = makeTerminalTask(name: "Task1", project: project, completionDate: now, context: ctx)

        let report = ReportLogic.buildReport(
            tasks: [task], milestones: [milestone], dateRange: .thisYear, now: now
        )

        #expect(report.projectGroups[0].milestones.isEmpty)
    }

    @Test("Milestone taskCount reflects assigned tasks")
    func milestoneTaskCount() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let milestone = Milestone(name: "v2.0", project: project, displayID: .permanent(3))
        ctx.insert(milestone)
        milestone.statusRawValue = MilestoneStatus.done.rawValue
        milestone.completionDate = now
        milestone.lastStatusChangeDate = now

        // Assign two tasks to the milestone
        let task1 = makeTerminalTask(name: "Task1", project: project, completionDate: now, context: ctx)
        task1.milestone = milestone
        let task2 = makeTerminalTask(name: "Task2", project: project, completionDate: now, context: ctx)
        task2.milestone = milestone

        let report = ReportLogic.buildReport(
            tasks: [task1, task2], milestones: [milestone], dateRange: .thisYear, now: now
        )

        #expect(report.projectGroups[0].milestones[0].taskCount == 2)
    }

    @Test("Project group created for milestone-only project (no tasks)")
    func milestoneOnlyProjectGroup() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "MilestoneOnly", context: ctx)

        let milestone = Milestone(name: "v1.0", project: project, displayID: .permanent(1))
        ctx.insert(milestone)
        milestone.statusRawValue = MilestoneStatus.done.rawValue
        milestone.completionDate = now
        milestone.lastStatusChangeDate = now

        let report = ReportLogic.buildReport(
            tasks: [], milestones: [milestone], dateRange: .thisYear, now: now
        )

        #expect(report.projectGroups.count == 1)
        #expect(report.projectGroups[0].projectName == "MilestoneOnly")
        #expect(report.projectGroups[0].tasks.isEmpty)
        #expect(report.projectGroups[0].milestones.count == 1)
    }

    @Test("No milestones results in empty milestones array")
    func emptyMilestones() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let task = makeTerminalTask(name: "Task1", project: project, completionDate: now, context: ctx)

        let report = ReportLogic.buildReport(
            tasks: [task], milestones: [], dateRange: .thisYear, now: now
        )

        #expect(report.projectGroups[0].milestones.isEmpty)
    }

    @Test("Task milestoneName populated when task has milestone")
    func taskMilestoneNamePopulated() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let milestone = Milestone(name: "Beta", project: project, displayID: .permanent(1))
        ctx.insert(milestone)

        let task = makeTerminalTask(name: "Task1", project: project, completionDate: now, context: ctx)
        task.milestone = milestone

        let report = ReportLogic.buildReport(
            tasks: [task], dateRange: .thisYear, now: now
        )

        #expect(report.projectGroups[0].tasks[0].milestoneName == "Beta")
    }

    @Test("Task milestoneName nil when task has no milestone")
    func taskMilestoneNameNil() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let task = makeTerminalTask(name: "Task1", project: project, completionDate: now, context: ctx)

        let report = ReportLogic.buildReport(
            tasks: [task], dateRange: .thisYear, now: now
        )

        #expect(report.projectGroups[0].tasks[0].milestoneName == nil)
    }
}
