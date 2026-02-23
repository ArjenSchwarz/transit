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

    @Test("Milestones without completionDate excluded")
    func milestonesWithoutCompletionDateExcluded() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let milestone = Milestone(name: "No Date", project: project, displayID: .permanent(1))
        ctx.insert(milestone)
        milestone.statusRawValue = MilestoneStatus.done.rawValue
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

// MARK: - ReportMarkdownFormatter Milestone Tests

@MainActor
@Suite("ReportMarkdownFormatter Milestones")
struct ReportMarkdownFormatterMilestoneTests {

    @Test("Markdown includes milestones section when milestones present")
    func markdownIncludesMilestonesSection() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "Alpha",
                    tasks: [
                        ReportTask(
                            id: UUID(), displayID: "T-1", name: "Task",
                            taskType: .feature, isAbandoned: false,
                            completionDate: .now, permanentDisplayId: 1,
                            milestoneName: nil
                        )
                    ],
                    milestones: [
                        ReportMilestone(
                            id: UUID(), displayID: "M-1", name: "v1.0",
                            isAbandoned: false, taskCount: 3
                        )
                    ]
                )
            ],
            totalDone: 1,
            totalAbandoned: 0
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("### Milestones"))
        #expect(output.contains("- M-1: v1.0 (3 tasks)"))
    }

    @Test("Markdown omits milestones section when no milestones")
    func markdownOmitsMilestonesSection() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "Alpha",
                    tasks: [
                        ReportTask(
                            id: UUID(), displayID: "T-1", name: "Task",
                            taskType: .feature, isAbandoned: false,
                            completionDate: .now, permanentDisplayId: 1,
                            milestoneName: nil
                        )
                    ],
                    milestones: []
                )
            ],
            totalDone: 1,
            totalAbandoned: 0
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(!output.contains("### Milestones"))
    }

    @Test("Abandoned milestone rendered with strikethrough")
    func abandonedMilestoneStrikethrough() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "Project",
                    tasks: [],
                    milestones: [
                        ReportMilestone(
                            id: UUID(), displayID: "M-2", name: "Dropped",
                            isAbandoned: true, taskCount: 1
                        )
                    ]
                )
            ],
            totalDone: 0,
            totalAbandoned: 0
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("- ~~M-2: Dropped~~ (Abandoned, 1 task)"))
    }

    @Test("Milestone with 1 task uses singular form")
    func milestoneSingularTask() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "Project",
                    tasks: [],
                    milestones: [
                        ReportMilestone(
                            id: UUID(), displayID: "M-1", name: "Solo",
                            isAbandoned: false, taskCount: 1
                        )
                    ]
                )
            ],
            totalDone: 0,
            totalAbandoned: 0
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("- M-1: Solo (1 task)"))
    }

    @Test("Task line includes milestone name suffix")
    func taskMilestoneNameSuffix() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "Project",
                    tasks: [
                        ReportTask(
                            id: UUID(), displayID: "T-5", name: "Add login",
                            taskType: .feature, isAbandoned: false,
                            completionDate: .now, permanentDisplayId: 5,
                            milestoneName: "v1.0"
                        )
                    ],
                    milestones: []
                )
            ],
            totalDone: 1,
            totalAbandoned: 0
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("- T-5: Feature: Add login [v1.0]"))
    }

    @Test("Task line without milestone has no suffix")
    func taskNoMilestoneSuffix() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "Project",
                    tasks: [
                        ReportTask(
                            id: UUID(), displayID: "T-5", name: "Add login",
                            taskType: .feature, isAbandoned: false,
                            completionDate: .now, permanentDisplayId: 5,
                            milestoneName: nil
                        )
                    ],
                    milestones: []
                )
            ],
            totalDone: 1,
            totalAbandoned: 0
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("- T-5: Feature: Add login"))
        #expect(!output.contains("["))
    }

    @Test("Abandoned task with milestone shows both markers")
    func abandonedTaskWithMilestone() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "Project",
                    tasks: [
                        ReportTask(
                            id: UUID(), displayID: "T-3", name: "Old feature",
                            taskType: .feature, isAbandoned: true,
                            completionDate: .now, permanentDisplayId: 3,
                            milestoneName: "v1.0"
                        )
                    ],
                    milestones: []
                )
            ],
            totalDone: 0,
            totalAbandoned: 1
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("- ~~T-3: Feature: Old feature~~ (Abandoned) [v1.0]"))
    }
}
