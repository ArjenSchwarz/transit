import Foundation
import Testing
@testable import Transit

@MainActor
struct DisplayIDAllocatorTests {

    // MARK: - provisionalID

    @Test func provisionalIDReturnsProvisional() {
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let result = allocator.provisionalID()

        #expect(result == .provisional)
    }

    @Test func provisionalIDFormatsAsBullet() {
        let store = InMemoryCounterStore()
        let allocator = DisplayIDAllocator(store: store)
        let result = allocator.provisionalID()

        #expect(result.formatted == "T-\u{2022}")
    }

    // MARK: - allocateNextID with InMemoryCounterStore

    @Test func allocateNextIDReturnsSequentialIDs() async throws {
        let store = InMemoryCounterStore(initialNextDisplayID: 1)
        let allocator = DisplayIDAllocator(store: store)

        let first = try await allocator.allocateNextID()
        let second = try await allocator.allocateNextID()
        let third = try await allocator.allocateNextID()

        #expect(first == 1)
        #expect(second == 2)
        #expect(third == 3)
    }

    @Test func allocateNextIDRetriesOnConflict() async throws {
        let store = InMemoryCounterStore(initialNextDisplayID: 10)
        await store.enqueueSaveOutcomes([.conflict, .success])
        let allocator = DisplayIDAllocator(store: store)

        let id = try await allocator.allocateNextID()
        #expect(id == 10)

        let attempts = await store.saveAttemptCount
        #expect(attempts == 2) // first was conflict, second succeeded
    }

    @Test func allocateNextIDThrowsAfterMaxRetries() async throws {
        let store = InMemoryCounterStore(initialNextDisplayID: 1)
        // Queue more conflicts than the retry limit
        await store.enqueueSaveOutcomes(
            Array(repeating: .conflict, count: 5)
        )
        let allocator = DisplayIDAllocator(store: store, retryLimit: 3)

        await #expect(throws: DisplayIDAllocator.Error.retriesExhausted) {
            try await allocator.allocateNextID()
        }
    }

    // MARK: - Promotion sort order (conceptual)

    @Test func promotionSortOrderIsCreationDateAscending() {
        let project = Project(name: "P", description: "Test", gitRepo: nil, colorHex: "#000000")

        let earlier = TransitTask(name: "First", type: .feature, project: project, displayID: .provisional)
        earlier.creationDate = Date(timeIntervalSince1970: 1000)

        let later = TransitTask(name: "Second", type: .feature, project: project, displayID: .provisional)
        later.creationDate = Date(timeIntervalSince1970: 2000)

        let tasks = [later, earlier].sorted { $0.creationDate < $1.creationDate }

        #expect(tasks.first?.name == "First")
        #expect(tasks.last?.name == "Second")
    }

    @Test func taskWithPermanentIDIsNotProvisional() {
        let project = Project(name: "P", description: "Test", gitRepo: nil, colorHex: "#000000")
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .permanent(42))

        #expect(task.permanentDisplayId == 42)
        #expect(task.displayID == .permanent(42))
    }

    @Test func taskWithProvisionalIDHasNilPermanentDisplayId() {
        let project = Project(name: "P", description: "Test", gitRepo: nil, colorHex: "#000000")
        let task = TransitTask(name: "Task", type: .feature, project: project, displayID: .provisional)

        #expect(task.permanentDisplayId == nil)
        #expect(task.displayID == .provisional)
    }
}
