#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct PortfolioSummaryServiceTests {
    @Test func allBucketsDerivedCountsEmptyProjectsAndNoBodies() throws {
        let fixture = try MCPPortfolioSavedFixture()
        let summary = try summarize(fixture.capture())
        let project = try #require(summary.projects.first { $0.projectId == fixture.project.id })
        #expect(project.countsByStatus == MCPPortfolioFixture.expectedCounts)
        #expect(project.totalTaskCount == 9)
        #expect(project.ideaCount == 2 && project.inProgressCount == 1)
        #expect(project.workflowTaskCount == 5 && project.nonterminalTaskCount == 7)
        #expect(project.recentCompletions == MCPPortfolioFixture.expectedCompletions)
        #expect(summary.completionWindow == MCPPortfolioFixture.window)
        let empty = try #require(
            summary.projects.first { $0.projectId == MCPPortfolioFixture.emptyProjectID })
        #expect(PortfolioSummaryTestValues.buckets(empty.countsByStatus) == Array(repeating: 0, count: 8))
        #expect(
            empty.totalTaskCount == 0 && empty.lastRecordedActivity == nil && empty.milestones.isEmpty)
        let invalid = try #require(project.diagnostics.first { $0.category == "invalid_task_status" })
        #expect(invalid.affectedCount == 1 && invalid.sampleComplete && invalid.samples.count == 1)
        let rendering = String(reflecting: summary)
        for forbidden in [
            "Captured description", "Canonical comment coverage", "taskDescription", "metadata"
        ] {
            #expect(!rendering.contains(forbidden))
        }
    }

    @Test func emptyPortfolioIsSuccessfulAndHasEightZeroOrphanBuckets() throws {
        let view = try MCPPortfolioSavedFixture().capture()
        let summary = try summarize(
            PortfolioSummaryTestValues.view(
                view, projects: [], tasks: [], milestones: [], comments: []
            ))
        #expect(summary.projects.isEmpty && summary.diagnostics.isEmpty)
        #expect(summary.unresolvedProjects.totalTaskCount == 0)
        #expect(
            PortfolioSummaryTestValues.buckets(summary.unresolvedProjects.countsByStatus)
                == Array(repeating: 0, count: 8))
    }

    @Test(arguments: ["open", "done", "abandoned", "future-status"])
    func milestoneRawStatusIsIndependentOfTerminalTasks(raw: String) throws {
        let view = try MCPPortfolioSavedFixture().capture()
        let milestone = try #require(
            view.milestones.first { $0.id == MCPPortfolioFixture.openMilestoneID })
        let changed = PortfolioSummaryTestValues.milestone(milestone, status: raw)
        let tasks = view.tasks.map {
            PortfolioSummaryTestValues.task($0, status: "done", milestoneKey: .some(changed.physicalKey))
        }
        let summary = try summarize(
            PortfolioSummaryTestValues.view(view, tasks: tasks, milestones: [changed]))
        let output = try #require(summary.projects.flatMap(\.milestones).first)
        #expect(output.rawStatus == raw)
        #expect(output.status == (raw == "future-status" ? "open" : raw))
        #expect(output.invalidStatus == (raw == "future-status"))
        #expect(output.countsByStatus.done == tasks.count)
        #expect(output.displayId == milestone.permanentDisplayId)
    }

    @Test func emptyMilestonesAndMissingDisplayIDsStayPresent() throws {
        let view = try MCPPortfolioSavedFixture().capture()
        let milestones = view.milestones.map {
            PortfolioSummaryTestValues.milestone($0, displayID: .some(nil))
        }
        let summary = try summarize(
            PortfolioSummaryTestValues.view(view, tasks: [], milestones: milestones, comments: []))
        let output = summary.projects.flatMap(\.milestones)
        #expect(output.count == 2 && output.allSatisfy { $0.displayId == nil })
        #expect(
            output.allSatisfy {
                PortfolioSummaryTestValues.buckets($0.countsByStatus) == Array(repeating: 0, count: 8)
            })
    }

    @Test func completionWindowEdgesRestorationAndMissingDates() throws {
        let view = try MCPPortfolioSavedFixture().capture()
        let window = MCPPortfolioFixture.window
        let statuses = [
            "done", "done", "done", "abandoned", "abandoned", "abandoned", "done", "planning", "unknown"
        ]
        let dates: [Date?] = [
            window.start, window.end, window.start.addingTimeInterval(-0.001),
            window.start, window.end.addingTimeInterval(-0.001), window.end, nil,
            window.start, window.start
        ]
        let ordered = view.tasks.sorted { $0.id.uuidString < $1.id.uuidString }
        let tasks = zip(ordered, statuses.indices).map { task, index in
            PortfolioSummaryTestValues.task(
                task, status: statuses[index], completion: .some(dates[index]))
        }
        let summary = try summarize(PortfolioSummaryTestValues.view(view, tasks: tasks))
        let project = try #require(
            summary.projects.first { $0.projectId == MCPPortfolioFixture.populatedProjectID })
        #expect(
            project.recentCompletions
                == PortfolioRecentCompletions(done: 1, abandoned: 2, missingCompletionDateCount: 1))
        #expect(project.countsByStatus.done == 4 && project.countsByStatus.abandoned == 3)
    }

    @Test func orphanAndInvalidMilestonePartitionsCountPhysicalRecordsExactlyOnce() throws {
        let view = try MCPPortfolioSavedFixture().capture()
        let tasks = view.tasks.sorted { $0.id.uuidString < $1.id.uuidString }
        let milestone = try #require(view.milestones.first)
        let foreign = try #require(view.projects.first { $0.id == MCPPortfolioFixture.emptyProjectID })
        let foreignMilestone = PortfolioSummaryTestValues.milestone(
            milestone, projectKey: .some(foreign.physicalKey))
        let nonexistent = LocalRecordKey(encodedIdentifier: Data("unresolved-endpoint".utf8))
        let changed = [
            PortfolioSummaryTestValues.task(tasks[0], projectKey: .some(nil)),
            PortfolioSummaryTestValues.task(tasks[1], projectKey: .some(nonexistent)),
            PortfolioSummaryTestValues.task(tasks[2], milestoneKey: .some(foreignMilestone.physicalKey)),
            PortfolioSummaryTestValues.task(tasks[3], milestoneKey: .some(nonexistent)),
            PortfolioSummaryTestValues.task(tasks[4], milestoneKey: .some(nil))
        ]
        let summary = try summarize(
            PortfolioSummaryTestValues.view(view, tasks: changed, milestones: [foreignMilestone]))
        let project = try #require(
            summary.projects.first { $0.projectId == MCPPortfolioFixture.populatedProjectID })
        #expect(summary.unresolvedProjects.totalTaskCount == 2)
        #expect(project.totalTaskCount == 3 && project.invalidMilestoneAssociations.totalTaskCount == 2)
        #expect(project.unassignedMilestone.totalTaskCount == 1)
        #expect(summary.projects.flatMap(\.milestones).allSatisfy { $0.totalTaskCount == 0 })
        #expect(project.totalTaskCount + summary.unresolvedProjects.totalTaskCount == changed.count)
    }

    @Test func insufficientCaptureFailsWithTypedCoherenceError() throws {
        let view = try MCPPortfolioSavedFixture().capture()
        #expect(throws: PortfolioSummaryError.incoherentCapture) {
            try summarize(PortfolioSummaryTestValues.view(view, completeness: .selectedRead))
        }
        #expect(throws: PortfolioSummaryError.incoherentCapture) {
            try summarize(PortfolioSummaryTestValues.view(view, scope: .selectedQuery))
        }
    }

    private func summarize(_ view: CapturedReadView) throws -> PortfolioSummary {
        try PortfolioSummaryService.summarize(view: view, window: MCPPortfolioFixture.window)
    }
}

extension PortfolioSummaryServiceTests {
    @Test(arguments: [
        "task_creation", "task_status", "comment_creation", "milestone_creation", "milestone_status"
    ])
    func everyActivityKindCanWin(kind: String) throws {
        let view = try MCPPortfolioSavedFixture().capture()
        let baseline = MCPPortfolioFixture.window.start.addingTimeInterval(-600)
        let latest = MCPPortfolioFixture.window.end.addingTimeInterval(600)
        let tasks = view.tasks.map {
            PortfolioSummaryTestValues.task(
                $0, creation: kind == "task_creation" ? latest : baseline,
                statusChange: kind == "task_status" ? latest : baseline
            )
        }
        let milestones = view.milestones.map {
            PortfolioSummaryTestValues.milestone(
                $0, creation: kind == "milestone_creation" ? latest : baseline,
                statusChange: kind == "milestone_status" ? latest : baseline
            )
        }
        let comments = view.comments.map {
            PortfolioSummaryTestValues.comment(
                $0, creation: kind == "comment_creation" ? latest : baseline
            )
        }
        let summary = try summarize(
            PortfolioSummaryTestValues.view(
                view, tasks: tasks, milestones: milestones, comments: comments))
        let evidence = try #require(
            summary.projects.first { $0.projectId == MCPPortfolioFixture.populatedProjectID }?
                .lastRecordedActivity)
        #expect(evidence.timestamp == latest && evidence.kind.rawValue == kind)
        let expectedIDs =
            kind.hasPrefix("task_")
            ? tasks.map(\.id) : (kind.hasPrefix("milestone_") ? milestones.map(\.id) : comments.map(\.id))
        #expect(evidence.id == expectedIDs.min { $0.uuidString < $1.uuidString })
    }

    @Test func tiedActivityUsesLexicalKindThenIdentityAndOrphanCommentsDoNotInventActivity() throws {
        let view = try MCPPortfolioSavedFixture().capture()
        let tie = MCPPortfolioFixture.window.end
        let tasks = view.tasks.map {
            PortfolioSummaryTestValues.task($0, creation: tie, statusChange: tie)
        }
        let milestones = view.milestones.map {
            PortfolioSummaryTestValues.milestone($0, creation: tie, statusChange: tie)
        }
        let comments = view.comments.map { PortfolioSummaryTestValues.comment($0, creation: tie) }
        let summary = try summarize(
            PortfolioSummaryTestValues.view(
                view, tasks: tasks, milestones: milestones, comments: comments))
        let evidence = try #require(
            summary.projects.first { $0.projectId == MCPPortfolioFixture.populatedProjectID }?
                .lastRecordedActivity)
        #expect(evidence.kind == .commentCreation && evidence.id == MCPPortfolioFixture.commentID)
        let orphanComments = comments.map {
            PortfolioSummaryTestValues.comment($0, creation: tie, taskKey: .some(nil))
        }
        let empty = try summarize(
            PortfolioSummaryTestValues.view(view, tasks: [], milestones: [], comments: orphanComments))
        #expect(empty.projects.allSatisfy { $0.lastRecordedActivity == nil })
    }

    @Test func milestoneOnlyActivityIsIncluded() throws {
        let view = try MCPPortfolioSavedFixture().capture()
        let summary = try summarize(PortfolioSummaryTestValues.view(view, tasks: [], comments: []))
        let project = try #require(
            summary.projects.first { $0.projectId == MCPPortfolioFixture.populatedProjectID })
        #expect(project.lastRecordedActivity?.kind == .milestoneCreation)
        #expect(
            project.lastRecordedActivity?.id
                == view.milestones.map(\.id).min { $0.uuidString < $1.uuidString })
    }

    @Test func namesAndDisplayIDsNeverMergeAndDiagnosticSamplingIsStable() throws {
        let view = try MCPPortfolioSavedFixture(taskCount: 24).capture()
        let projects = view.projects.enumerated().map { index, project in
            PortfolioSummaryTestValues.project(project, name: index == 0 ? " Shared " : "SHARED")
        }
        let tasks = view.tasks.map { PortfolioSummaryTestValues.task($0, displayID: .some(7)) }
        let milestones = view.milestones.map {
            PortfolioSummaryTestValues.milestone($0, displayID: .some(8))
        }
        let changed = PortfolioSummaryTestValues.view(
            view, projects: projects, tasks: tasks, milestones: milestones)
        let summary = try summarize(changed)
        #expect(
            summary.projects.count == 2 && summary.projects.reduce(0) { $0 + $1.totalTaskCount } == 24)
        #expect(summary.projects.flatMap(\.milestones).count == 2)
        let diagnostics = summary.diagnostics + summary.projects.flatMap(\.diagnostics)
        let taskCollision = try #require(diagnostics.first { $0.category == "duplicate_task_display_id" })
        #expect(
            taskCollision.affectedCount == 24 && taskCollision.samples.count == 10
                && !taskCollision.sampleComplete)
        #expect(
            taskCollision.samples.map(\.id)
                == tasks.map(\.id).sorted { $0.uuidString < $1.uuidString }.prefix(10).map { $0 })
        let nameCollision = try #require(diagnostics.first { $0.category == "duplicate_project_name" })
        #expect(
            nameCollision.affectedCount == 2 && nameCollision.samples.count == 2
                && nameCollision.sampleComplete)
        let milestoneCollision = try #require(
            diagnostics.first { $0.category == "duplicate_milestone_display_id" })
        #expect(milestoneCollision.affectedCount == 2 && milestoneCollision.sampleComplete)
        let reversed = try summarize(
            PortfolioSummaryTestValues.view(
                changed, projects: Array(projects.reversed()), tasks: Array(tasks.reversed()),
                milestones: Array(milestones.reversed())
            ))
        #expect(reversed == summary)
    }

    @Test func duplicateUUIDWithinScopeOrEnteringItsIdentityClosureFailsExplicitly() throws {
        let view = try MCPPortfolioSavedFixture().capture()
        let selected = try #require(
            view.projects.first { $0.id == MCPPortfolioFixture.populatedProjectID })
        let foreign = try #require(view.projects.first { $0.id == MCPPortfolioFixture.emptyProjectID })
        let tasks = view.tasks.sorted { $0.id.uuidString < $1.id.uuidString }
        let duplicateTasks = [tasks[0], PortfolioSummaryTestValues.task(tasks[1], id: tasks[0].id)]
        #expect(throws: PortfolioSummaryError.identityAmbiguity) {
            try summarize(PortfolioSummaryTestValues.view(view, tasks: duplicateTasks))
        }
        let enteringDuplicate = PortfolioSummaryTestValues.task(
            tasks[1], id: tasks[0].id, projectKey: .some(foreign.physicalKey))
        #expect(throws: PortfolioSummaryError.identityAmbiguity) {
            try summarize(PortfolioSummaryTestValues.view(
                view, scope: .projects([selected.physicalKey]), tasks: [tasks[0], enteringDuplicate]))
        }
        let duplicateProjects = [selected, PortfolioSummaryTestValues.project(foreign, id: selected.id)]
        #expect(throws: PortfolioSummaryError.identityAmbiguity) {
            try summarize(
                PortfolioSummaryTestValues.view(
                    view, scope: .projects([selected.physicalKey]), projects: duplicateProjects))
        }
        let milestone = try #require(view.milestones.first)
        let other = try #require(view.milestones.first { $0.physicalKey != milestone.physicalKey })
        #expect(throws: PortfolioSummaryError.identityAmbiguity) {
            try summarize(
                PortfolioSummaryTestValues.view(
                    view,
                    milestones: [
                        milestone, PortfolioSummaryTestValues.milestone(other, id: milestone.id)
                    ]
                ))
        }
    }

    @Test func unrelatedDuplicateUUIDsDoNotFailOrWidenScopedSummary() throws {
        let view = try MCPPortfolioSavedFixture().capture()
        let selected = try #require(
            view.projects.first { $0.id == MCPPortfolioFixture.populatedProjectID })
        let foreign = try #require(view.projects.first { $0.id == MCPPortfolioFixture.emptyProjectID })
        let tasks = view.tasks.sorted { $0.id.uuidString < $1.id.uuidString }
        let foreignTasks = [tasks[0], tasks[1]].map {
            PortfolioSummaryTestValues.task(
                $0, id: UUID(uuidString: "00000000-0000-4002-8000-000000000001")!,
                projectKey: .some(foreign.physicalKey), milestoneKey: .some(nil))
        }
        let selectedTasks = Array(tasks.dropFirst(2))
        let summary = try summarize(
            PortfolioSummaryTestValues.view(
                view, scope: .projects([selected.physicalKey]), tasks: selectedTasks + foreignTasks
            ))
        #expect(summary.projects.count == 1 && summary.projects.first?.projectId == selected.id)
        #expect(summary.projects.first?.totalTaskCount == selectedTasks.count)
        #expect(summary.unresolvedProjects.totalTaskCount == 0)
    }
}
#endif
