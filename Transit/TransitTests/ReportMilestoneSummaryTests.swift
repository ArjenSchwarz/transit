import Foundation
import SwiftData
import Testing
@testable import Transit

// MARK: - Milestone Summary Count Tests
//
// Bug: report summaries only counted tasks, so a report containing only terminal
// milestones (no matching terminal tasks) rendered misleading summaries like
// "0 tasks (0 done)" / "0 done". Milestones must be reflected in both top-level
// and per-project summary counts.

@MainActor
@Suite(.serialized)
struct ReportMilestoneSummaryTests {

    // MARK: - ProjectGroup milestone counts

    @Test("Milestone-only project group reports milestone done count, not zero")
    func milestoneOnlyGroupReportsMilestoneDone() throws {
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

        let group = report.projectGroups[0]
        #expect(group.doneMilestoneCount == 1)
        #expect(group.abandonedMilestoneCount == 0)
    }

    @Test("Abandoned milestone counted in abandonedMilestoneCount")
    func abandonedMilestoneCounted() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let milestone = Milestone(name: "Dropped", project: project, displayID: .permanent(2))
        ctx.insert(milestone)
        milestone.statusRawValue = MilestoneStatus.abandoned.rawValue
        milestone.completionDate = now
        milestone.lastStatusChangeDate = now

        let report = ReportLogic.buildReport(
            tasks: [], milestones: [milestone], dateRange: .thisYear, now: now
        )

        let group = report.projectGroups[0]
        #expect(group.doneMilestoneCount == 0)
        #expect(group.abandonedMilestoneCount == 1)
    }

    // MARK: - Top-level totals

    @Test("Top-level totals include milestone counts")
    func topLevelTotalsIncludeMilestones() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let doneMilestone = Milestone(name: "v1.0", project: project, displayID: .permanent(1))
        ctx.insert(doneMilestone)
        doneMilestone.statusRawValue = MilestoneStatus.done.rawValue
        doneMilestone.completionDate = now
        doneMilestone.lastStatusChangeDate = now

        let abandonedMilestone = Milestone(name: "Dropped", project: project, displayID: .permanent(2))
        ctx.insert(abandonedMilestone)
        abandonedMilestone.statusRawValue = MilestoneStatus.abandoned.rawValue
        abandonedMilestone.completionDate = now
        abandonedMilestone.lastStatusChangeDate = now

        let report = ReportLogic.buildReport(
            tasks: [], milestones: [doneMilestone, abandonedMilestone], dateRange: .thisYear, now: now
        )

        #expect(report.totalMilestonesDone == 1)
        #expect(report.totalMilestonesAbandoned == 1)
    }

    // MARK: - Formatter

    @Test("Markdown summary mentions milestones for milestone-only report")
    func markdownSummaryMentionsMilestones() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "MilestoneOnly",
                    tasks: [],
                    milestones: [
                        ReportMilestone(
                            id: UUID(), displayID: "M-1", name: "v1.0",
                            isAbandoned: false, taskCount: 0
                        )
                    ]
                )
            ],
            totalDone: 0,
            totalAbandoned: 0,
            totalMilestonesDone: 1,
            totalMilestonesAbandoned: 0
        )

        let output = ReportMarkdownFormatter.format(data)
        // Must not render the misleading "0 tasks (0 done)" with no milestone mention.
        #expect(output.contains("**0 tasks** (0 done, 1 milestone done)"))
        #expect(!output.contains("**0 tasks** (0 done)\n"))
    }

    @Test("Task-only report summary unchanged (no milestone mention)")
    func taskOnlySummaryUnchanged() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "Project",
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
            totalAbandoned: 0,
            totalMilestonesDone: 0,
            totalMilestonesAbandoned: 0
        )

        let output = ReportMarkdownFormatter.format(data)
        #expect(output.contains("**1 task** (1 done)"))
        #expect(!output.contains("milestone"))
    }

    @Test("Mixed tasks + milestones summary combines both counts")
    func mixedTasksAndMilestonesSummary() {
        let data = ReportData(
            dateRangeLabel: "This Week",
            projectGroups: [
                ProjectGroup(
                    id: UUID(),
                    projectName: "Mixed",
                    tasks: [
                        ReportTask(
                            id: UUID(), displayID: "T-1", name: "TaskA",
                            taskType: .feature, isAbandoned: false,
                            completionDate: .now, permanentDisplayId: 1,
                            milestoneName: nil
                        ),
                        ReportTask(
                            id: UUID(), displayID: "T-2", name: "TaskB",
                            taskType: .bug, isAbandoned: false,
                            completionDate: .now, permanentDisplayId: 2,
                            milestoneName: nil
                        )
                    ],
                    milestones: [
                        ReportMilestone(
                            id: UUID(), displayID: "M-1", name: "v1.0",
                            isAbandoned: false, taskCount: 2
                        )
                    ]
                )
            ],
            totalDone: 2,
            totalAbandoned: 0,
            totalMilestonesDone: 1,
            totalMilestonesAbandoned: 0
        )

        let output = ReportMarkdownFormatter.format(data)
        // Top-level header and per-project summary both combine task and milestone counts.
        #expect(output.contains("**2 tasks** (2 done, 1 milestone done)"))
        #expect(output.contains("2 done, 1 milestone done"))
    }
}
