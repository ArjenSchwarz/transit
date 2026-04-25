import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor
@Suite(.serialized)
struct DisplayIDMaintenanceServiceScanTests {

    // MARK: - Helpers

    private func makeService(context: ModelContext) -> DisplayIDMaintenanceService {
        let taskAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let milestoneAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let commentService = CommentService(modelContext: context)
        return DisplayIDMaintenanceService(
            modelContext: context,
            taskAllocator: taskAllocator,
            taskCounterStore: InMemoryCounterStore(),
            milestoneAllocator: milestoneAllocator,
            milestoneCounterStore: InMemoryCounterStore(),
            commentService: commentService
        )
    }

    private func makeProject(in context: ModelContext, name: String = "Test") -> Project {
        let project = Project(name: name, description: "", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    private func makeTask(
        in context: ModelContext, project: Project, name: String,
        displayId: Int?, creationDate: Date = Date.now, id: UUID = UUID()
    ) -> TransitTask {
        let display: DisplayID = displayId.map { .permanent($0) } ?? .provisional
        let task = TransitTask(name: name, type: .feature, project: project, displayID: display)
        task.id = id
        task.creationDate = creationDate
        context.insert(task)
        return task
    }

    private func makeMilestone(
        in context: ModelContext, project: Project, name: String,
        displayId: Int?, creationDate: Date = Date.now, id: UUID = UUID()
    ) -> Milestone {
        let display: DisplayID = displayId.map { .permanent($0) } ?? .provisional
        let milestone = Milestone(name: name, project: project, displayID: display)
        milestone.id = id
        milestone.creationDate = creationDate
        context.insert(milestone)
        return milestone
    }

    // MARK: - Tests

    @Test func emptyContextReturnsEmptyGroups() throws {
        let context = try TestModelContainer.newContext()
        let service = makeService(context: context)

        let report = try service.scanDuplicates()
        #expect(report.tasks.isEmpty)
        #expect(report.milestones.isEmpty)
    }

    @Test func twoTasksSharingDisplayIdReportedOnce() throws {
        let context = try TestModelContainer.newContext()
        let project = makeProject(in: context)
        _ = makeTask(in: context, project: project, name: "A", displayId: 5,
                     creationDate: Date(timeIntervalSince1970: 1000))
        _ = makeTask(in: context, project: project, name: "B", displayId: 5,
                     creationDate: Date(timeIntervalSince1970: 2000))
        try context.save()

        let service = makeService(context: context)
        let report = try service.scanDuplicates()

        #expect(report.tasks.count == 1)
        #expect(report.tasks.first?.displayId == 5)
        #expect(report.tasks.first?.records.count == 2)
        #expect(report.milestones.isEmpty)
    }

    @Test func twoMilestonesSharingDisplayIdReportedOnce() throws {
        let context = try TestModelContainer.newContext()
        let project = makeProject(in: context)
        _ = makeMilestone(in: context, project: project, name: "M-Old", displayId: 3,
                          creationDate: Date(timeIntervalSince1970: 1000))
        _ = makeMilestone(in: context, project: project, name: "M-New", displayId: 3,
                          creationDate: Date(timeIntervalSince1970: 2000))
        try context.save()

        let service = makeService(context: context)
        let report = try service.scanDuplicates()

        #expect(report.milestones.count == 1)
        #expect(report.milestones.first?.displayId == 3)
        #expect(report.milestones.first?.records.count == 2)
        #expect(report.tasks.isEmpty)
    }

    @Test func provisionalRecordsExcluded() throws {
        let context = try TestModelContainer.newContext()
        let project = makeProject(in: context)
        _ = makeTask(in: context, project: project, name: "A", displayId: nil)
        _ = makeTask(in: context, project: project, name: "B", displayId: nil)
        _ = makeMilestone(in: context, project: project, name: "M1", displayId: nil)
        _ = makeMilestone(in: context, project: project, name: "M2", displayId: nil)
        try context.save()

        let service = makeService(context: context)
        let report = try service.scanDuplicates()

        #expect(report.tasks.isEmpty)
        #expect(report.milestones.isEmpty)
    }

    @Test func taskAndMilestoneSharingIntegerIsNotADuplicate() throws {
        let context = try TestModelContainer.newContext()
        let project = makeProject(in: context)
        _ = makeTask(in: context, project: project, name: "T-5", displayId: 5)
        _ = makeMilestone(in: context, project: project, name: "M-5", displayId: 5)
        try context.save()

        let service = makeService(context: context)
        let report = try service.scanDuplicates()
        #expect(report.tasks.isEmpty)
        #expect(report.milestones.isEmpty)
    }

    @Test func oldestCreationDateWins() throws {
        let context = try TestModelContainer.newContext()
        let project = makeProject(in: context)
        let oldId = UUID()
        let newId = UUID()
        _ = makeTask(in: context, project: project, name: "Newer", displayId: 7,
                     creationDate: Date(timeIntervalSince1970: 2000), id: newId)
        _ = makeTask(in: context, project: project, name: "Older", displayId: 7,
                     creationDate: Date(timeIntervalSince1970: 1000), id: oldId)
        try context.save()

        let service = makeService(context: context)
        let report = try service.scanDuplicates()

        let group = try #require(report.tasks.first)
        let winner = try #require(group.records.first)
        #expect(winner.id == oldId)
        #expect(winner.role == .winner)
        #expect(winner.name == "Older")
        #expect(group.records.last?.id == newId)
        #expect(group.records.last?.role == .loser)
    }

    @Test func uuidAscendingTiebreakerWhenCreationDateEqual() throws {
        let context = try TestModelContainer.newContext()
        let project = makeProject(in: context)
        let date = Date(timeIntervalSince1970: 1000)
        let uuidA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let uuidB = UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFE")!
        _ = makeTask(in: context, project: project, name: "B", displayId: 9,
                     creationDate: date, id: uuidB)
        _ = makeTask(in: context, project: project, name: "A", displayId: 9,
                     creationDate: date, id: uuidA)
        try context.save()

        let service = makeService(context: context)
        let report = try service.scanDuplicates()

        let group = try #require(report.tasks.first)
        #expect(group.records.first?.id == uuidA, "Lex-smallest UUID wins on tie")
        #expect(group.records.last?.id == uuidB)
    }

    @Test func projectNilYieldsNoProjectLiteral() throws {
        let context = try TestModelContainer.newContext()
        let project = makeProject(in: context)
        let orphan1 = makeTask(in: context, project: project, name: "Orphan1", displayId: 11)
        let orphan2 = makeTask(in: context, project: project, name: "Orphan2", displayId: 11)
        try context.save()
        // After save, drop their project association.
        orphan1.project = nil
        orphan2.project = nil
        try context.save()

        let service = makeService(context: context)
        let report = try service.scanDuplicates()
        let group = try #require(report.tasks.first)
        for record in group.records {
            #expect(record.projectName == "(no project)")
        }
    }

    @Test func groupsOrderedByAscendingDisplayId() throws {
        let context = try TestModelContainer.newContext()
        let project = makeProject(in: context)
        _ = makeTask(in: context, project: project, name: "A1", displayId: 7)
        _ = makeTask(in: context, project: project, name: "A2", displayId: 7)
        _ = makeTask(in: context, project: project, name: "B1", displayId: 2)
        _ = makeTask(in: context, project: project, name: "B2", displayId: 2)
        _ = makeTask(in: context, project: project, name: "C1", displayId: 5)
        _ = makeTask(in: context, project: project, name: "C2", displayId: 5)
        try context.save()

        let service = makeService(context: context)
        let report = try service.scanDuplicates()

        let displayIds = report.tasks.map(\.displayId)
        #expect(displayIds == [2, 5, 7])
    }

    @Test func winnerFirstOrderingPreservedAcrossManyLosers() throws {
        let context = try TestModelContainer.newContext()
        let project = makeProject(in: context)
        let winnerId = UUID()
        _ = makeTask(in: context, project: project, name: "Loser1", displayId: 4,
                     creationDate: Date(timeIntervalSince1970: 3000))
        _ = makeTask(in: context, project: project, name: "Winner", displayId: 4,
                     creationDate: Date(timeIntervalSince1970: 1000), id: winnerId)
        _ = makeTask(in: context, project: project, name: "Loser2", displayId: 4,
                     creationDate: Date(timeIntervalSince1970: 5000))
        try context.save()

        let service = makeService(context: context)
        let report = try service.scanDuplicates()
        let group = try #require(report.tasks.first)
        #expect(group.records.count == 3)
        #expect(group.records[0].id == winnerId)
        #expect(group.records[0].role == .winner)
        #expect(group.records[1].role == .loser)
        #expect(group.records[2].role == .loser)
    }
}
