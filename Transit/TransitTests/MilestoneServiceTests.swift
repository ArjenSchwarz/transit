import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MilestoneServiceTests {

    // MARK: - Helpers

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

    private func makeTask(in context: ModelContext, project: Project) -> TransitTask {
        let task = TransitTask(name: "Test Task", type: .feature, project: project, displayID: .permanent(1))
        StatusEngine.initializeNewTask(task)
        context.insert(task)
        return task
    }

    // MARK: - createMilestone

    @Test func createMilestoneCreatesInOpenStatus() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)

        let milestone = try await service.createMilestone(name: "v1.0", description: "First release", project: project)

        #expect(milestone.name == "v1.0")
        #expect(milestone.milestoneDescription == "First release")
        #expect(milestone.status == .open)
        #expect(milestone.project?.id == project.id)
        #expect(milestone.completionDate == nil)
    }

    @Test func createMilestoneAssignsDisplayID() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)
        #expect(milestone.permanentDisplayId != nil)
    }

    @Test func createMilestoneTrimsAndValidatesName() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)

        await #expect(throws: MilestoneService.Error.invalidName) {
            try await service.createMilestone(name: "   ", description: nil, project: project)
        }

        let milestone = try await service.createMilestone(name: "  Trimmed  ", description: nil, project: project)
        #expect(milestone.name == "Trimmed")
    }

    @Test func createMilestoneEnforcesCaseInsensitiveUniqueness() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        _ = try await service.createMilestone(name: "v1.0", description: nil, project: project)

        await #expect(throws: MilestoneService.Error.duplicateName) {
            try await service.createMilestone(name: "V1.0", description: nil, project: project)
        }
    }

    @Test func createMilestoneAllowsSameNameInDifferentProjects() async throws {
        let (service, context) = try makeService()
        let projectA = makeProject(in: context, name: "Project A")
        let projectB = makeProject(in: context, name: "Project B")

        let milestoneA = try await service.createMilestone(name: "v1.0", description: nil, project: projectA)
        let milestoneB = try await service.createMilestone(name: "v1.0", description: nil, project: projectB)

        #expect(milestoneA.name == milestoneB.name)
        #expect(milestoneA.project?.id != milestoneB.project?.id)
    }

    @Test func createMilestoneWithProvisionalIDOnAllocatorFailure() async throws {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        await store.enqueueSaveOutcomes([.failure(DisplayIDAllocator.Error.retriesExhausted)])
        let allocator = DisplayIDAllocator(store: store, retryLimit: 1)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        let project = makeProject(in: context)

        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)
        #expect(milestone.displayID == .provisional)
    }

    // MARK: - updateMilestone

    @Test func updateMilestoneChangesName() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)

        try service.updateMilestone(milestone, name: "v2.0", description: nil)
        #expect(milestone.name == "v2.0")
    }

    @Test func updateMilestoneChangesDescription() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: "Old", project: project)

        try service.updateMilestone(milestone, name: nil, description: "New description")
        #expect(milestone.milestoneDescription == "New description")
    }

    @Test func updateMilestoneRejectsDuplicateName() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        _ = try await service.createMilestone(name: "v1.0", description: nil, project: project)
        let second = try await service.createMilestone(name: "v2.0", description: nil, project: project)

        #expect(throws: MilestoneService.Error.duplicateName) {
            try service.updateMilestone(second, name: "v1.0", description: nil)
        }
    }

    @Test func updateMilestoneAllowsKeepingOwnName() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)

        try service.updateMilestone(milestone, name: "v1.0", description: "Updated")
        #expect(milestone.name == "v1.0")
        #expect(milestone.milestoneDescription == "Updated")
    }

    @Test func updateMilestoneRejectsEmptyName() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)

        #expect(throws: MilestoneService.Error.invalidName) {
            try service.updateMilestone(milestone, name: "   ", description: nil)
        }
    }

    // MARK: - updateStatus

    @Test func updateStatusSetsLastStatusChangeDate() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)
        let originalDate = milestone.lastStatusChangeDate

        try await Task.sleep(for: .milliseconds(10))
        try service.updateStatus(milestone, to: .done)

        #expect(milestone.status == .done)
        #expect(milestone.lastStatusChangeDate > originalDate)
    }

    @Test func updateStatusToDoneSetsCompletionDate() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)

        try service.updateStatus(milestone, to: .done)
        #expect(milestone.completionDate != nil)
    }

    @Test func updateStatusToAbandonedSetsCompletionDate() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)

        try service.updateStatus(milestone, to: .abandoned)
        #expect(milestone.completionDate != nil)
    }

    @Test func updateStatusToOpenClearsCompletionDate() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)

        try service.updateStatus(milestone, to: .done)
        #expect(milestone.completionDate != nil)

        try service.updateStatus(milestone, to: .open)
        #expect(milestone.completionDate == nil)
    }

    // MARK: - deleteMilestone

    @Test func deleteMilestoneRemovesFromContext() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)
        let milestoneID = milestone.id

        try service.deleteMilestone(milestone)

        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.id == milestoneID }
        )
        #expect(try context.fetch(descriptor).isEmpty)
    }

    @Test func deleteMilestoneNullifiesTaskAssignment() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)
        let task = makeTask(in: context, project: project)
        try service.setMilestone(milestone, on: task)

        try service.deleteMilestone(milestone)
        #expect(task.milestone == nil)
    }

    // MARK: - setMilestone

    @Test func setMilestoneAssignsMilestoneToTask() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)
        let task = makeTask(in: context, project: project)

        try service.setMilestone(milestone, on: task)
        #expect(task.milestone?.id == milestone.id)
    }

    @Test func setMilestoneNilClearsAssignment() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)
        let task = makeTask(in: context, project: project)
        try service.setMilestone(milestone, on: task)

        try service.setMilestone(nil, on: task)
        #expect(task.milestone == nil)
    }

    @Test func setMilestoneThrowsProjectMismatch() async throws {
        let (service, context) = try makeService()
        let projectA = makeProject(in: context, name: "Project A")
        let projectB = makeProject(in: context, name: "Project B")
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: projectA)
        let task = makeTask(in: context, project: projectB)

        #expect(throws: MilestoneService.Error.projectMismatch) {
            try service.setMilestone(milestone, on: task)
        }
    }

    @Test func setMilestoneThrowsProjectRequired() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)
        let task = TransitTask(name: "Orphan", type: .feature, project: project, displayID: .permanent(99))
        StatusEngine.initializeNewTask(task)
        context.insert(task)
        task.project = nil

        #expect(throws: MilestoneService.Error.projectRequired) {
            try service.setMilestone(milestone, on: task)
        }
    }

}
