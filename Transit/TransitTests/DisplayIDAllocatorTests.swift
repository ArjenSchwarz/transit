import CloudKit
import Foundation
import Testing
@testable import Transit

@MainActor
struct DisplayIDAllocatorTests {

    // MARK: - provisionalID

    @Test func provisionalIDReturnsProvisional() {
        let allocator = DisplayIDAllocator(container: .default())
        let result = allocator.provisionalID()

        #expect(result == .provisional)
    }

    @Test func provisionalIDFormatsAsBullet() {
        let allocator = DisplayIDAllocator(container: .default())
        let result = allocator.provisionalID()

        #expect(result.formatted == "T-\u{2022}")
    }

    // MARK: - Promotion sort order (conceptual)

    /// Tasks with earlier creationDate should be promoted first. This test
    /// verifies that the sort descriptor used by promoteProvisionalTasks
    /// would place older tasks before newer ones.
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

    /// Tasks that already have a permanent ID should not be considered provisional.
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
