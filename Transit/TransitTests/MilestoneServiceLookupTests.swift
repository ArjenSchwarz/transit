import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MilestoneServiceLookupTests {

    // MARK: - Helpers

    private func makeService() throws -> (MilestoneService, ModelContext) {
        let context = try TestModelContainer.newContext()
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let service = MilestoneService(modelContext: context, displayIDAllocator: allocator)
        return (service, context)
    }

    private func makeProject(in context: ModelContext) -> Project {
        let project = Project(name: "Test Project", description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    // MARK: - findByID

    @Test func findByIDReturnsCorrectMilestone() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)

        let found = try service.findByID(milestone.id)
        #expect(found.name == "v1.0")
    }

    @Test func findByIDThrowsForNonExistent() throws {
        let (service, _) = try makeService()
        #expect(throws: MilestoneService.Error.milestoneNotFound) {
            try service.findByID(UUID())
        }
    }

    // MARK: - findByDisplayID

    @Test func findByDisplayIDReturnsCorrectMilestone() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)

        let found = try service.findByDisplayID(milestone.permanentDisplayId!)
        #expect(found.name == "v1.0")
    }

    @Test func findByDisplayIDThrowsForNonExistent() throws {
        let (service, _) = try makeService()
        #expect(throws: MilestoneService.Error.milestoneNotFound) {
            try service.findByDisplayID(999)
        }
    }

    // MARK: - findByName

    @Test func findByNameReturnsCaseInsensitiveMatch() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        _ = try await service.createMilestone(name: "v1.0", description: nil, project: project)

        let found = service.findByName("V1.0", in: project)
        #expect(found?.name == "v1.0")
    }

    @Test func findByNameReturnsNilWhenNotFound() throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        #expect(service.findByName("nonexistent", in: project) == nil)
    }

    // MARK: - milestonesForProject

    @Test func milestonesForProjectReturnsFilteredByStatus() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        _ = try await service.createMilestone(name: "v1.0", description: nil, project: project)
        let done = try await service.createMilestone(name: "v2.0", description: nil, project: project)
        try service.updateStatus(done, to: .done)

        #expect(service.milestonesForProject(project).count == 2)
        let openOnly = service.milestonesForProject(project, status: .open)
        #expect(openOnly.count == 1)
        #expect(openOnly.first?.name == "v1.0")
    }

    // MARK: - milestoneNameExists

    @Test func milestoneNameExistsChecksCaseInsensitive() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        _ = try await service.createMilestone(name: "v1.0", description: nil, project: project)

        #expect(service.milestoneNameExists("V1.0", in: project))
        #expect(!service.milestoneNameExists("v2.0", in: project))
    }

    @Test func milestoneNameExistsExcludesSpecifiedID() async throws {
        let (service, context) = try makeService()
        let project = makeProject(in: context)
        let milestone = try await service.createMilestone(name: "v1.0", description: nil, project: project)

        #expect(!service.milestoneNameExists("v1.0", in: project, excluding: milestone.id))
    }
}
