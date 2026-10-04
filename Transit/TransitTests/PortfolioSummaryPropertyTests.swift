#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

extension PortfolioSummaryServiceTests {
    @Test(arguments: [UInt64(1), 17, 2382, 0xC0FFEE])
    // swiftlint:disable:next function_body_length
    func seededPhysicalRecordPartitionsMatchIndependentFilters(seed: UInt64) throws {
        let fixture = try MCPPortfolioSavedFixture(taskCount: 127)
        let projects = try fixture.owner.context.fetch(FetchDescriptor<Project>())
        let foreign = try #require(projects.first { $0.id == MCPPortfolioFixture.emptyProjectID })
        let milestones = try fixture.owner.context.fetch(FetchDescriptor<Milestone>())
        let localMilestone = try #require(
            milestones.first { $0.id == MCPPortfolioFixture.openMilestoneID })
        let foreignMilestone = Milestone(name: "Foreign", project: foreign, displayID: .permanent(99))
        foreignMilestone.id = UUID(uuidString: "00000000-0000-4003-8000-000000000001")!
        fixture.owner.context.insert(foreignMilestone)
        var random = PortfolioSummarySeed(state: seed)
        let rawStatuses = PortfolioSummaryTestValues.statuses + ["legacy", "", "IN-PROGRESS"]
        let offsets: [TimeInterval?] = [nil, -0.001, 0, 1, 3_599.999, 3_600, 3_601]
        for task in fixture.tasks {
            task.statusRawValue = rawStatuses[random.next(rawStatuses.count)]
            switch random.next(5) {
            case 0: task.project = nil
            case 1: task.project = foreign
            default: task.project = fixture.project
            }
            switch random.next(3) {
            case 0: task.milestone = nil
            case 1: task.milestone = localMilestone
            default: task.milestone = foreignMilestone
            }
            task.completionDate = offsets[random.next(offsets.count)].map {
                MCPPortfolioFixture.window.start.addingTimeInterval($0)
            }
        }
        try fixture.owner.context.save()
        let captured = try fixture.capture()
        let summary = try PortfolioSummaryService.summarize(
            view: captured, window: MCPPortfolioFixture.window)
        for project in summary.projects {
            let identity = try #require(captured.projects.first { $0.id == project.projectId })
            let records = captured.tasks.filter { $0.projectKey == identity.physicalKey }
            #expect(
                PortfolioSummaryTestValues.buckets(project.countsByStatus)
                    == PortfolioSummaryTestValues.referenceBuckets(records))
            #expect(project.totalTaskCount == records.count)
            #expect(
                project.totalTaskCount
                    == PortfolioSummaryTestValues.buckets(project.countsByStatus).reduce(0, +))
            #expect(project.ideaCount == project.countsByStatus.idea)
            #expect(project.inProgressCount == project.countsByStatus.inProgress)
            #expect(
                project.workflowTaskCount
                    == PortfolioSummaryTestValues.buckets(project.countsByStatus)[1...5].reduce(0, +))
            #expect(project.nonterminalTaskCount == project.ideaCount + project.workflowTaskCount)
            #expect(
                project.recentCompletions
                    == PortfolioSummaryTestValues.referenceCompletions(
                        records, window: MCPPortfolioFixture.window))
            try checkPartitions(project, identity: identity, records: records, captured: captured)
        }
        let projectKeys = Set(captured.projects.map(\.physicalKey))
        let orphans = captured.tasks.filter { $0.projectKey.map { !projectKeys.contains($0) } ?? true }
        #expect(summary.unresolvedProjects.totalTaskCount == orphans.count)
        #expect(
            PortfolioSummaryTestValues.buckets(summary.unresolvedProjects.countsByStatus)
                == PortfolioSummaryTestValues.referenceBuckets(orphans))
        #expect(
            summary.projects.reduce(0) { $0 + $1.totalTaskCount }
                + summary.unresolvedProjects.totalTaskCount == captured.tasks.count)
        let permuted = PortfolioSummaryTestValues.view(
            captured, projects: random.shuffled(captured.projects),
            tasks: random.shuffled(captured.tasks),
            milestones: random.shuffled(captured.milestones), comments: random.shuffled(captured.comments)
        )
        #expect(
            try PortfolioSummaryService.summarize(view: permuted, window: MCPPortfolioFixture.window)
                == summary)
    }

    private func checkPartitions(
        _ project: PortfolioProjectSummary, identity: ReadProject, records: [ReadTask],
        captured: CapturedReadView
    ) throws {
        let unassigned = records.filter { $0.milestoneKey == nil }
        let invalid = records.filter { task in
            guard let key = task.milestoneKey else { return false }
            return !captured.milestones.contains {
                $0.physicalKey == key && $0.projectKey == identity.physicalKey
            }
        }
        #expect(
            PortfolioSummaryTestValues.buckets(project.unassignedMilestone.countsByStatus)
                == PortfolioSummaryTestValues.referenceBuckets(unassigned))
        #expect(
            PortfolioSummaryTestValues.buckets(project.invalidMilestoneAssociations.countsByStatus)
                == PortfolioSummaryTestValues.referenceBuckets(invalid))
        #expect(
            project.unassignedMilestone.recentCompletions
                == PortfolioSummaryTestValues.referenceCompletions(
                    unassigned, window: MCPPortfolioFixture.window))
        #expect(
            project.invalidMilestoneAssociations.recentCompletions
                == PortfolioSummaryTestValues.referenceCompletions(
                    invalid, window: MCPPortfolioFixture.window))
        for milestone in project.milestones {
            let endpoint = try #require(captured.milestones.first { $0.id == milestone.milestoneId })
            let selected = records.filter { $0.milestoneKey == endpoint.physicalKey }
            #expect(
                PortfolioSummaryTestValues.buckets(milestone.countsByStatus)
                    == PortfolioSummaryTestValues.referenceBuckets(selected))
            #expect(milestone.totalTaskCount == selected.count)
            #expect(
                milestone.recentCompletions
                    == PortfolioSummaryTestValues.referenceCompletions(
                        selected, window: MCPPortfolioFixture.window))
        }
        #expect(
            project.milestones.reduce(0) { $0 + $1.totalTaskCount } + unassigned.count + invalid.count
                == project.totalTaskCount)
    }
}

@MainActor @Suite(.serialized)
struct PortfolioCompletionWindowTests {
    @Test(arguments: [
        "2026-10-03T00:00:00Z", "2026-10-03T00:00:00.0Z",
        "2026-10-03T00:00:00.00Z", "2026-10-03T00:00:00.000Z",
        "2026-10-03T02:00:00+02:00", "2026-10-02T19:00:00-05:00"
    ])
    func offsetsAndSupportedFractionPrecisionPreserveInstant(start: String) throws {
        let parsed = try CompletionWindow.parse(start: start, end: "2026-10-03T01:00:00Z")
        #expect(parsed == MCPPortfolioFixture.window)
    }

    @Test(arguments: ["1", "12", "123"])
    func nonzeroFractionalSecondsAreNotRoundedAway(fraction: String) throws {
        let parsed = try CompletionWindow.parse(
            start: "2026-10-03T00:00:00.\(fraction)Z", end: "2026-10-03T01:00:00Z"
        )
        let expected = Double("0.\(fraction)")!
        #expect(
            abs(parsed.start.timeIntervalSince(MCPPortfolioFixture.window.start) - expected) < 0.000_001)
    }

    @Test(arguments: [
        "", "2026-10-03", "2026-10-03T00:00:00", "2026-10-03T00:00Z",
        "2026-10-03T00:00:00.1234Z", "2026-10-03T00:00:00.Z",
        "2026-02-30T00:00:00Z", "2026-13-03T00:00:00Z", "2026-10-00T00:00:00Z",
        "2026-10-03T24:00:00Z", "2026-10-03T00:60:00Z", "2026-10-03T00:00:60Z",
        "2026-10-03T00:00:00+0200", "2026-10-03T00:00:00+24:00",
        "2026-10-03T00:00:00+00:60", "2026-10-03T00:00:00Z trailing",
        " 2026-10-03T00:00:00Z", "2026-10-03t00:00:00z", "20261003T000000Z"
    ])
    func strictMalformedInputsHaveTypedValidationFailure(input: String) {
        #expect(throws: CompletionWindowError.invalidInput) {
            try CompletionWindow.parse(start: input, end: "2026-10-03T01:00:00Z")
        }
        #expect(throws: CompletionWindowError.invalidInput) {
            try CompletionWindow.parse(start: "2026-10-02T00:00:00Z", end: input)
        }
    }

    @Test(arguments: ["2026-10-03T00:00:00Z", "2026-10-02T23:59:59.999Z"])
    func equalOrReversedIntervalsFail(end: String) {
        #expect(throws: CompletionWindowError.invalidInput) {
            try CompletionWindow.parse(start: "2026-10-03T00:00:00Z", end: end)
        }
    }
}
#endif
