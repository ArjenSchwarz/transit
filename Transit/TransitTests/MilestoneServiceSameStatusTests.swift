import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-923: `MilestoneService.updateStatus` must treat same-status
/// updates as no-ops for status side effects. Otherwise an old `done`/`abandoned`
/// milestone re-enters the current report window through `ReportLogic`'s
/// `completionDate ?? lastStatusChangeDate` fallback.
@MainActor @Suite(.serialized)
struct MilestoneServiceSameStatusTests {

    private func makeService() throws -> (MilestoneService, ModelContext) {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        return (service, context)
    }

    private func makeProject(in context: ModelContext, name: String = "Test Project") -> Project {
        let project = Project(name: name, description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    /// Re-submitting the same terminal status must not rewrite `completionDate`.
    @Test func updateStatusSameTerminalStatusPreservesCompletionDate() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)

        try service.updateStatus(milestone, to: .done)
        let originalCompletionDate = try #require(milestone.completionDate)
        let originalLastStatusChangeDate = milestone.lastStatusChangeDate

        try await Task.sleep(for: .milliseconds(10))
        try service.updateStatus(milestone, to: .done)

        #expect(milestone.completionDate == originalCompletionDate)
        #expect(milestone.lastStatusChangeDate == originalLastStatusChangeDate)
    }

    /// Re-submitting the same non-terminal status must not rewrite `lastStatusChangeDate`.
    @Test func updateStatusSameOpenStatusPreservesLastStatusChangeDate() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)
        let originalLastStatusChangeDate = milestone.lastStatusChangeDate

        try await Task.sleep(for: .milliseconds(10))
        try service.updateStatus(milestone, to: .open)

        #expect(milestone.lastStatusChangeDate == originalLastStatusChangeDate)
        #expect(milestone.completionDate == nil)
    }

    /// Re-submitting an abandoned status must not rewrite the completion timestamp.
    @Test func updateStatusSameAbandonedStatusPreservesCompletionDate() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)

        try service.updateStatus(milestone, to: .abandoned)
        let originalCompletionDate = try #require(milestone.completionDate)
        let originalLastStatusChangeDate = milestone.lastStatusChangeDate

        try await Task.sleep(for: .milliseconds(10))
        try service.updateStatus(milestone, to: .abandoned)

        #expect(milestone.completionDate == originalCompletionDate)
        #expect(milestone.lastStatusChangeDate == originalLastStatusChangeDate)
    }
}
