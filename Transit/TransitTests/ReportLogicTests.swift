import Foundation
import SwiftData
import Testing
@testable import Transit

// MARK: - Grouping and Sorting Tests

@MainActor
@Suite(.serialized)
struct ReportLogicGroupingTests {

    @Test("Tasks are grouped by project")
    func tasksGroupedByProject() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let projA = makeTestProject(name: "Alpha", context: ctx)
        let projB = makeTestProject(name: "Beta", context: ctx)

        let taskA1 = makeTerminalTask(name: "A1", project: projA, completionDate: now, context: ctx)
        let taskA2 = makeTerminalTask(name: "A2", project: projA, completionDate: now, context: ctx)
        let taskB1 = makeTerminalTask(name: "B1", project: projB, completionDate: now, context: ctx)

        let report = ReportLogic.buildReport(tasks: [taskA1, taskA2, taskB1], dateRange: .thisYear, now: now)

        #expect(report.projectGroups.count == 2)
        #expect(report.projectGroups[0].projectName == "Alpha")
        #expect(report.projectGroups[0].tasks.count == 2)
        #expect(report.projectGroups[1].projectName == "Beta")
        #expect(report.projectGroups[1].tasks.count == 1)
    }

    @Test("Projects sorted alphabetically case-insensitive")
    func projectsSortedCaseInsensitive() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let projZ = makeTestProject(name: "Zebra", context: ctx)
        let projA = makeTestProject(name: "alpha", context: ctx)
        let projB = makeTestProject(name: "Beta", context: ctx)

        let taskZ = makeTerminalTask(name: "Z1", project: projZ, completionDate: now, context: ctx)
        let taskA = makeTerminalTask(name: "A1", project: projA, completionDate: now, context: ctx)
        let taskB = makeTerminalTask(name: "B1", project: projB, completionDate: now, context: ctx)

        let report = ReportLogic.buildReport(tasks: [taskZ, taskA, taskB], dateRange: .thisYear, now: now)

        #expect(report.projectGroups.count == 3)
        #expect(report.projectGroups[0].projectName == "alpha")
        #expect(report.projectGroups[1].projectName == "Beta")
        #expect(report.projectGroups[2].projectName == "Zebra")
    }

    @Test("Tasks sorted by completionDate ascending")
    func tasksSortedByCompletionDate() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let taskLate = makeTerminalTask(
            name: "Late", project: project,
            displayID: .permanent(3), completionDate: now, context: ctx
        )
        let taskEarly = makeTerminalTask(
            name: "Early", project: project,
            displayID: .permanent(1), completionDate: now.addingTimeInterval(-3600), context: ctx
        )
        let taskMid = makeTerminalTask(
            name: "Mid", project: project,
            displayID: .permanent(2), completionDate: now.addingTimeInterval(-1800), context: ctx
        )

        let report = ReportLogic.buildReport(
            tasks: [taskLate, taskEarly, taskMid], dateRange: .thisYear, now: now
        )

        let names = report.projectGroups[0].tasks.map(\.name)
        #expect(names == ["Early", "Mid", "Late"])
    }

    @Test("Tasks with same completionDate sorted by permanentDisplayId, nil last")
    func tasksSortedByDisplayIdTiebreak() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let taskId10 = makeTerminalTask(
            name: "ID-10", project: project,
            displayID: .permanent(10), completionDate: now, context: ctx
        )
        let taskId2 = makeTerminalTask(
            name: "ID-2", project: project,
            displayID: .permanent(2), completionDate: now, context: ctx
        )
        let taskNoId = makeTerminalTask(
            name: "No-ID", project: project,
            displayID: .provisional, completionDate: now, context: ctx
        )

        let report = ReportLogic.buildReport(
            tasks: [taskId10, taskId2, taskNoId], dateRange: .thisYear, now: now
        )

        let names = report.projectGroups[0].tasks.map(\.name)
        #expect(names == ["ID-2", "ID-10", "No-ID"])
    }

    @Test("UUID tiebreaker when completionDate and displayId match")
    func tasksSortedByUUIDFallback() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let taskOne = makeTerminalTask(
            name: "Task1", project: project, completionDate: now, context: ctx
        )
        let taskTwo = makeTerminalTask(
            name: "Task2", project: project, completionDate: now, context: ctx
        )

        let report = ReportLogic.buildReport(
            tasks: [taskOne, taskTwo], dateRange: .thisYear, now: now
        )

        let tasks = report.projectGroups[0].tasks
        #expect(tasks.count == 2)
        #expect(tasks[0].id.uuidString < tasks[1].id.uuidString)
    }
}

// MARK: - Filtering Tests

@MainActor
@Suite(.serialized)
struct ReportLogicFilterTests {

    @Test("Only terminal tasks (done/abandoned) are included")
    func onlyTerminalTasksIncluded() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let done = makeTerminalTask(name: "Done", project: project, completionDate: now, context: ctx)
        let abandoned = makeTerminalTask(
            name: "Abandoned", project: project,
            status: .abandoned, completionDate: now, context: ctx
        )
        let active = makeNonTerminalTask(name: "Active", project: project, context: ctx)
        let idea = makeNonTerminalTask(name: "Idea", project: project, status: .idea, context: ctx)

        let report = ReportLogic.buildReport(
            tasks: [done, abandoned, active, idea], dateRange: .thisYear, now: now
        )

        let names = report.projectGroups.flatMap(\.tasks).map(\.name)
        #expect(names.contains("Done"))
        #expect(names.contains("Abandoned"))
        #expect(!names.contains("Active"))
        #expect(!names.contains("Idea"))
    }

    @Test("Tasks with nil completionDate are excluded")
    func nilCompletionDateExcluded() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let normal = makeTerminalTask(name: "Normal", project: project, completionDate: now, context: ctx)

        let broken = TransitTask(name: "Broken", type: .feature, project: project, displayID: .provisional)
        ctx.insert(broken)
        broken.statusRawValue = TaskStatus.done.rawValue
        broken.completionDate = nil

        let report = ReportLogic.buildReport(tasks: [normal, broken], dateRange: .thisYear, now: now)

        let names = report.projectGroups.flatMap(\.tasks).map(\.name)
        #expect(names == ["Normal"])
    }

    @Test("Orphan tasks with nil project are excluded")
    func orphanTasksExcluded() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let normal = makeTerminalTask(name: "Normal", project: project, completionDate: now, context: ctx)

        let orphan = TransitTask(name: "Orphan", type: .feature, project: project, displayID: .provisional)
        ctx.insert(orphan)
        StatusEngine.initializeNewTask(orphan, now: now.addingTimeInterval(-100))
        StatusEngine.applyTransition(task: orphan, to: .done, now: now)
        orphan.project = nil

        let report = ReportLogic.buildReport(tasks: [normal, orphan], dateRange: .thisYear, now: now)

        let names = report.projectGroups.flatMap(\.tasks).map(\.name)
        #expect(names == ["Normal"])
    }

    @Test("Summary counts correct for done and abandoned")
    func summaryCounts() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let done1 = makeTerminalTask(name: "Done1", project: project, completionDate: now, context: ctx)
        let done2 = makeTerminalTask(name: "Done2", project: project, completionDate: now, context: ctx)
        let abn = makeTerminalTask(
            name: "Abn", project: project, status: .abandoned, completionDate: now, context: ctx
        )

        let report = ReportLogic.buildReport(tasks: [done1, done2, abn], dateRange: .thisYear, now: now)

        #expect(report.totalDone == 2)
        #expect(report.totalAbandoned == 1)
        #expect(report.totalTasks == 3)
    }

    @Test("Abandoned tasks marked as isAbandoned in ReportTask")
    func abandonedTaskIdentification() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let done = makeTerminalTask(name: "Done", project: project, completionDate: now, context: ctx)
        let abandoned = makeTerminalTask(
            name: "Abandoned", project: project, status: .abandoned, completionDate: now, context: ctx
        )

        let report = ReportLogic.buildReport(tasks: [done, abandoned], dateRange: .thisYear, now: now)

        let tasks = report.projectGroups[0].tasks
        #expect(tasks.first { $0.name == "Done" }?.isAbandoned == false)
        #expect(tasks.first { $0.name == "Abandoned" }?.isAbandoned == true)
    }

    @Test("Empty result for empty input")
    func emptyInput() throws {
        let report = ReportLogic.buildReport(tasks: [], dateRange: .thisWeek, now: reportTestNow)
        #expect(report.isEmpty)
        #expect(report.totalTasks == 0)
    }

    @Test("Provisional displayId uses DisplayID.formatted")
    func provisionalDisplayId() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let task = makeTerminalTask(
            name: "Provisional", project: project,
            displayID: .provisional, completionDate: now, context: ctx
        )

        let report = ReportLogic.buildReport(tasks: [task], dateRange: .thisYear, now: now)

        let reportTask = report.projectGroups[0].tasks[0]
        #expect(reportTask.displayID == DisplayID.provisional.formatted)
        #expect(reportTask.permanentDisplayId == nil)
    }

    @Test("Permanent displayId uses DisplayID.formatted")
    func permanentDisplayId() throws {
        let ctx = try makeReportTestContext()
        let now = reportTestNow
        let project = makeTestProject(name: "Project", context: ctx)

        let task = makeTerminalTask(
            name: "Permanent", project: project,
            displayID: .permanent(42), completionDate: now, context: ctx
        )

        let report = ReportLogic.buildReport(tasks: [task], dateRange: .thisYear, now: now)

        let reportTask = report.projectGroups[0].tasks[0]
        #expect(reportTask.displayID == "T-42")
        #expect(reportTask.permanentDisplayId == 42)
    }

    @Test("dateRangeLabel includes label and actual dates")
    func dateRangeLabel() throws {
        let report = ReportLogic.buildReport(tasks: [], dateRange: .thisWeek, now: reportTestNow)
        #expect(report.dateRangeLabel.hasPrefix("This Week ("))
        #expect(report.dateRangeLabel.hasSuffix(")"))
    }
}
