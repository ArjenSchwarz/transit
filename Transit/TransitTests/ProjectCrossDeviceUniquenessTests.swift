import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression coverage for T-2080. CloudKit identifies projects by UUID, so two
/// disconnected devices can each create the same normalized name and later sync
/// both records into one store. These tests simulate that import with independent
/// contexts sharing one container and intentionally bypass `createProject`.
@MainActor @Suite(.serialized)
struct ProjectCrossDeviceUniquenessTests {

    private struct Environment {
        let testContainer: TestModelContainer
        let winnerID: UUID
        let duplicateID: UUID
        let reservedCollisionID: UUID
    }

    private func makeSyncedDuplicateEnvironment() throws -> Environment {
        let testContainer = try TestModelContainer()
        let container = testContainer.container
        let winnerID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let duplicateID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let reservedCollisionID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))

        let firstDevice = ModelContext(container)
        let winner = Project(
            name: "Transit",
            description: "Created on device A",
            gitRepo: nil,
            colorHex: "#FF0000"
        )
        winner.id = winnerID
        firstDevice.insert(winner)
        let firstTask = TransitTask(
            name: "Device A task", type: .feature, project: winner, displayID: .permanent(10)
        )
        firstDevice.insert(firstTask)
        try firstDevice.save()

        let secondDevice = ModelContext(container)
        let duplicate = Project(
            name: "transit",
            description: "Created on device B",
            gitRepo: nil,
            colorHex: "#00FF00"
        )
        duplicate.id = duplicateID
        secondDevice.insert(duplicate)
        let secondTask = TransitTask(
            name: "Device B task", type: .bug, project: duplicate, displayID: .permanent(11)
        )
        secondDevice.insert(secondTask)

        // Force the reconciler to avoid a pre-existing generated-name collision.
        let reservedCollision = Project(
            name: "Transit (Duplicate \(duplicateID.uuidString))",
            description: "Existing project",
            gitRepo: nil,
            colorHex: "#0000FF"
        )
        reservedCollision.id = reservedCollisionID
        secondDevice.insert(reservedCollision)
        try secondDevice.save()

        return Environment(
            testContainer: testContainer,
            winnerID: winnerID,
            duplicateID: duplicateID,
            reservedCollisionID: reservedCollisionID
        )
    }

    @Test func nameLookupDoesNotChooseAnArbitrarySyncedDuplicate() throws {
        let environment = try makeSyncedDuplicateEnvironment()
        let receivingDevice = ModelContext(environment.testContainer.container)
        let service = ProjectService(modelContext: receivingDevice)

        let result = service.findProject(name: "TRANSIT")

        guard case .failure(.ambiguous) = result else {
            Issue.record("Expected synced duplicates to produce an ambiguous lookup")
            return
        }
    }

    @Test func postSyncMaintenanceReconcilesNamesWithoutDeletingProjectsOrTasks() throws {
        let environment = try makeSyncedDuplicateEnvironment()
        let receivingDevice = ModelContext(environment.testContainer.container)
        let service = ProjectService(modelContext: receivingDevice)

        #expect(try service.reconcileDuplicateNames() == 1)

        let projects = try receivingDevice.fetch(FetchDescriptor<Project>())
        #expect(projects.count == 3, "Reconciliation must preserve every synced project")
        #expect(Set(projects.map(\.id)) == [
            environment.winnerID,
            environment.duplicateID,
            environment.reservedCollisionID
        ])
        #expect(Set(projects.map { $0.name.lowercased() }).count == 3)
        #expect(projects.first { $0.id == environment.winnerID }?.name == "Transit")
        #expect(
            projects.first { $0.id == environment.duplicateID }?.name
                == "Transit (Duplicate \(environment.duplicateID.uuidString))-2",
            "The UUID winner and generated collision fallback must be deterministic"
        )

        let tasks = try receivingDevice.fetch(FetchDescriptor<TransitTask>())
        #expect(tasks.count == 2)
        #expect(Set(tasks.compactMap { $0.project?.id }) == [
            environment.winnerID,
            environment.duplicateID
        ], "Reconciliation must preserve task-to-project relationships")
        #expect(try service.reconcileDuplicateNames() == 0, "Reconciliation must be idempotent")
    }

    @Test func reconciliationDefersForUnsavedChangesAndCanRetry() throws {
        let environment = try makeSyncedDuplicateEnvironment()
        let receivingDevice = ModelContext(environment.testContainer.container)
        let service = ProjectService(modelContext: receivingDevice)
        let unrelated = Project(
            name: "Unsaved local edit",
            description: "Must not be committed by maintenance",
            gitRepo: nil,
            colorHex: "#FFFFFF"
        )
        receivingDevice.insert(unrelated)

        #expect(try service.reconcileDuplicateNames() == 0)
        #expect(receivingDevice.hasChanges)

        try receivingDevice.save()
        #expect(try service.reconcileDuplicateNames() == 1)
    }
}
