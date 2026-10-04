#if os(macOS)
import Foundation
import SwiftData
@testable import Transit

/// Deterministic fixture inputs and independently specified expectations.
/// Captures use the actual shared builder, never duplicate DTOs or fabricated revisions.
nonisolated enum MCPPortfolioFixture {
    static let populatedProjectID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let emptyProjectID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    static let openMilestoneID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    static let emptyDoneMilestoneID = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
    static let commentID = UUID(uuidString: "00000000-0000-4000-8000-000000000005")!

    // 2026-10-03 00:00:00Z to 01:00:00Z; no locale-dependent formatter or wall clock.
    static let window = CompletionWindow(
        start: Date(timeIntervalSince1970: 1_790_985_600),
        end: Date(timeIntervalSince1970: 1_790_989_200)
    )

    // Nine physical task records: each legal status once and one unknown raw status.
    // Both idea and unknown records belong to the open milestone; all others are unassigned.
    static let expectedCounts = PortfolioStatusCounts(
        idea: 2, planning: 1, spec: 1, readyForImplementation: 1,
        inProgress: 1, readyForReview: 1, done: 1, abandoned: 1
    )
    static let expectedTaskCount = 9
    static let expectedWorkflowCount = 5
    static let expectedNonterminalCount = 7

    // Done lies exactly at start; abandoned lies exactly at end and must be excluded.
    static let expectedCompletions = PortfolioRecentCompletions(
        done: 1, abandoned: 0, missingCompletionDateCount: 0
    )
}

@MainActor
struct MCPPortfolioSavedFixture {
    enum FixtureError: Error { case invalidTaskCount }
    let owner: TestModelContainer
    let tasks: [TransitTask]
    let project: Project
    let comment: Comment

    // swiftlint:disable:next function_body_length
    init(taskCount: Int = 9, commentOnEveryTask: Bool = false) throws {
        guard taskCount > 0 else { throw FixtureError.invalidTaskCount }
        owner = try TestModelContainer()
        owner.context.autosaveEnabled = false
        project = Project(name: "Populated", description: "", gitRepo: nil, colorHex: "blue")
        project.id = MCPPortfolioFixture.populatedProjectID
        let empty = Project(name: "Empty", description: "", gitRepo: nil, colorHex: "green")
        empty.id = MCPPortfolioFixture.emptyProjectID
        let open = Milestone(name: "Open", project: project, displayID: .permanent(1))
        open.id = MCPPortfolioFixture.openMilestoneID
        let done = Milestone(name: "Empty done", project: project, displayID: .permanent(2))
        done.id = MCPPortfolioFixture.emptyDoneMilestoneID
        done.statusRawValue = "done"
        for milestone in [open, done] {
            milestone.creationDate = MCPPortfolioFixture.window.start.addingTimeInterval(-120)
            milestone.lastStatusChangeDate = milestone.creationDate
        }
        owner.context.insert(project)
        owner.context.insert(empty)
        owner.context.insert(open)
        owner.context.insert(done)
        var records: [TransitTask] = []
        let statuses = ["idea", "planning", "spec", "ready-for-implementation", "in-progress",
                        "ready-for-review", "done", "abandoned", "unknown"]
        for index in 0..<taskCount {
            let task = TransitTask(name: "Task \(index)", type: .feature, project: project,
                                   displayID: .permanent(index + 1))
            task.id = UUID(uuidString: String(format: "00000000-0000-4001-8000-%012d", index + 1))!
            task.statusRawValue = statuses[index % statuses.count]
            task.creationDate = MCPPortfolioFixture.window.start.addingTimeInterval(-60)
            task.lastStatusChangeDate = task.creationDate
            if task.statusRawValue == "done" { task.completionDate = MCPPortfolioFixture.window.start }
            if task.statusRawValue == "abandoned" { task.completionDate = MCPPortfolioFixture.window.end }
            if index % 9 == 0 || index % 9 == 8 { task.milestone = open }
            task.taskDescription = "Captured description \(index)"
            task.metadata = ["fixture": "\(index)"]
            owner.context.insert(task)
            if commentOnEveryTask {
                let evidence = Comment(content: "Revision evidence \(index)", authorName: "Agent",
                                       isAgent: true, task: task)
                evidence.creationDate = task.creationDate
                owner.context.insert(evidence)
            }
            records.append(task)
        }
        tasks = records
        comment = Comment(content: "Canonical comment coverage", authorName: "Agent", isAgent: true,
                          task: records[min(6, records.count - 1)])
        comment.id = MCPPortfolioFixture.commentID
        comment.creationDate = MCPPortfolioFixture.window.end.addingTimeInterval(60)
        owner.context.insert(comment)
        try owner.context.save()
    }

    func capture() throws -> CapturedReadView {
        try MCPReadCaptureBuilder(container: owner.container, fence: .actorOnlyTestFixture).capture(Self.request)
    }

    static var request: ReadCaptureRequest {
        ReadCaptureRequest(projectSelectors: nil, selection: .portfolio,
                           completeness: .completePortfolio, includeComments: false)
    }
}
#endif
