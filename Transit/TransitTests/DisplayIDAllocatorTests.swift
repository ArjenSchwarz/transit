import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor
struct DisplayIDAllocatorTests {
    @Test
    func provisionalIDReturnsPendingMarker() {
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 1))
        #expect(allocator.provisionalID() == .provisional)
    }

    @Test
    func allocateNextIDRetriesOnConflict() async throws {
        let store = InMemoryCounterStore(initialNextDisplayID: 10)
        await store.enqueueSaveOutcomes([.conflict, .success])
        let allocator = DisplayIDAllocator(store: store, retryLimit: 3)

        let allocatedID = try await allocator.allocateNextID()

        #expect(allocatedID == 10)
        let attempts = await store.saveAttemptCount
        #expect(attempts == 2)
    }

    @Test
    func promoteProvisionalTasksUsesCreationOrder() async throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let project = Project(name: "Proj", description: "Desc", colorHex: "#00AA00")
        context.insert(project)

        let newer = TransitTask(
            name: "newer",
            creationDate: Date(timeIntervalSince1970: 300),
            lastStatusChangeDate: Date(timeIntervalSince1970: 300),
            project: project
        )
        let oldest = TransitTask(
            name: "oldest",
            creationDate: Date(timeIntervalSince1970: 100),
            lastStatusChangeDate: Date(timeIntervalSince1970: 100),
            project: project
        )
        let middle = TransitTask(
            name: "middle",
            creationDate: Date(timeIntervalSince1970: 200),
            lastStatusChangeDate: Date(timeIntervalSince1970: 200),
            project: project
        )

        context.insert(newer)
        context.insert(oldest)
        context.insert(middle)
        try context.save()

        let allocator = DisplayIDAllocator(store: InMemoryCounterStore(initialNextDisplayID: 7))

        await allocator.promoteProvisionalTasks(in: context)

        #expect(oldest.permanentDisplayId == 7)
        #expect(middle.permanentDisplayId == 8)
        #expect(newer.permanentDisplayId == 9)
    }

    @Test
    func promoteProvisionalTasksStopsOnFirstFailure() async throws {
        let container = try makeInMemoryModelContainer()
        let context = ModelContext(container)
        let project = Project(name: "Proj", description: "Desc", colorHex: "#AA0000")
        context.insert(project)

        let first = TransitTask(
            name: "first",
            creationDate: .distantPast,
            lastStatusChangeDate: .distantPast,
            project: project
        )
        let second = TransitTask(
            name: "second",
            creationDate: Date(timeIntervalSince1970: 1),
            lastStatusChangeDate: Date(timeIntervalSince1970: 1),
            project: project
        )
        let third = TransitTask(
            name: "third",
            creationDate: Date(timeIntervalSince1970: 2),
            lastStatusChangeDate: Date(timeIntervalSince1970: 2),
            project: project
        )
        context.insert(first)
        context.insert(second)
        context.insert(third)
        try context.save()

        let store = InMemoryCounterStore(initialNextDisplayID: 100)
        await store.enqueueSaveOutcomes([.success, .failure(MockCounterError.syntheticFailure), .success])
        let allocator = DisplayIDAllocator(store: store)

        await allocator.promoteProvisionalTasks(in: context)

        #expect(first.permanentDisplayId == 100)
        #expect(second.permanentDisplayId == nil)
        #expect(third.permanentDisplayId == nil)
    }
}
