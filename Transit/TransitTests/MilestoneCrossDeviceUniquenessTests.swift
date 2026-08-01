import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression coverage for T-1938. CloudKit identifies milestones by UUID, so two
/// disconnected devices can each create the same project-scoped name and later sync
/// both records into one store. These tests simulate that import with independent
/// contexts sharing one container; they intentionally bypass `createMilestone`, just
/// as CloudKit import bypasses service-layer validation.
@MainActor @Suite(.serialized)
struct MilestoneCrossDeviceUniquenessTests {

    private struct Environment {
        let container: ModelContainer
        let projectID: UUID
        let firstMilestoneID: UUID
        let secondMilestoneID: UUID
    }

    private func makeTask(
        named name: String,
        project: Project,
        milestone: Milestone,
        displayID: Int
    ) -> TransitTask {
        let task = TransitTask(
            name: name,
            type: .feature,
            project: project,
            displayID: .permanent(displayID)
        )
        task.milestone = milestone
        return task
    }

    private func makeSyncedDuplicateEnvironment() throws -> Environment {
        let container = try TestModelContainer.newContainer()

        let firstDevice = ModelContext(container)
        let project = Project(
            name: "Transit",
            description: "Test project",
            gitRepo: nil,
            colorHex: "#FF0000"
        )
        firstDevice.insert(project)
        let first = Milestone(
            name: "Beta",
            description: "Created on device A",
            project: project,
            displayID: .permanent(1)
        )
        first.creationDate = Date(timeIntervalSince1970: 1)
        firstDevice.insert(first)
        firstDevice.insert(makeTask(
            named: "Device A task", project: project, milestone: first, displayID: 10
        ))
        try firstDevice.save()

        let secondDevice = ModelContext(container)
        let projectID = project.id
        let projectDescriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == projectID }
        )
        let importedProject = try #require(try secondDevice.fetch(projectDescriptor).first)
        let second = Milestone(
            name: "beta",
            description: "Created on device B",
            project: importedProject,
            displayID: .permanent(2)
        )
        second.creationDate = Date(timeIntervalSince1970: 2)
        secondDevice.insert(second)
        secondDevice.insert(makeTask(
            named: "Device B task", project: importedProject, milestone: second, displayID: 11
        ))
        try secondDevice.save()

        return Environment(
            container: container,
            projectID: project.id,
            firstMilestoneID: first.id,
            secondMilestoneID: second.id
        )
    }

    private func makeService(in context: ModelContext) -> MilestoneService {
        MilestoneService(
            modelContext: context,
            displayIDAllocator: DisplayIDAllocator(
                store: InMemoryCounterStore(initialNextDisplayID: 3),
                isCloudSyncActive: true
            )
        )
    }

    @Test func nameLookupDoesNotChooseAnArbitrarySyncedDuplicate() throws {
        let environment = try makeSyncedDuplicateEnvironment()
        let receivingDevice = ModelContext(environment.container)
        let service = makeService(in: receivingDevice)
        let projectID = environment.projectID
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectID })
        let project = try #require(try receivingDevice.fetch(descriptor).first)

        #expect(throws: MilestoneService.Error.ambiguousName) {
            try service.findByName("BETA", in: project)
        }
    }

    @Test func postSyncMaintenanceReconcilesNamesWithoutDeletingRecords() async throws {
        let environment = try makeSyncedDuplicateEnvironment()
        let receivingDevice = ModelContext(environment.container)
        let service = makeService(in: receivingDevice)

        // App launch, foregrounding, and connectivity restoration already invoke this
        // hook after sync-related work. It must also repair UUID-distinct name conflicts.
        await service.promoteProvisionalMilestones()

        let milestones = try receivingDevice.fetch(FetchDescriptor<Milestone>())
        let normalizedNames = Set(milestones.map { $0.name.lowercased() })
        #expect(milestones.count == 2, "Reconciliation must preserve both synced records")
        #expect(normalizedNames.count == 2, "Reconciliation must restore unique project-scoped names")
        #expect(Set(milestones.map(\.id)) == [
            environment.firstMilestoneID,
            environment.secondMilestoneID
        ])
        #expect(
            milestones.first { $0.id == environment.firstMilestoneID }?.name == "Beta",
            "The deterministic oldest winner must keep its original name"
        )

        let tasks = try receivingDevice.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.count == 2)
        #expect(Set(tasks.compactMap { $0.milestone?.id }) == [
            environment.firstMilestoneID,
            environment.secondMilestoneID
        ], "Reconciliation must preserve both task assignments")
        #expect(try service.reconcileDuplicateNames() == 0, "Reconciliation must be idempotent")
    }

    @Test func mcpCreateTaskReportsAmbiguousMilestoneName() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context, name: "Transit")
        env.context.insert(Milestone(
            name: "Beta",
            description: nil,
            project: project,
            displayID: .permanent(1)
        ))
        env.context.insert(Milestone(
            name: "beta",
            description: nil,
            project: project,
            displayID: .permanent(2)
        ))
        try env.context.save()

        let request = MCPTestHelpers.toolCallRequest(
            tool: "create_task",
            arguments: [
                "name": "Must not be created",
                "type": "feature",
                "project": "Transit",
                "milestone": "BETA"
            ]
        )
        let response = await env.handler.handle(request)

        #expect(try MCPTestHelpers.isError(response))
        #expect(try MCPTestHelpers.errorText(response).contains("Multiple milestones named"))
        #expect(try env.taskService.fetchAllTasks().isEmpty)
    }
}
