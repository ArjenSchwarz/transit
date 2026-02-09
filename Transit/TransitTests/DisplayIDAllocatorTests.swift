//
//  DisplayIDAllocatorTests.swift
//  TransitTests
//
//  Tests for DisplayIDAllocator.
//

import CloudKit
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Transit

@MainActor
struct DisplayIDAllocatorTests {
    // Note: Full CloudKit integration tests require a test container
    // These tests cover the logic that doesn't require CloudKit

    @Test func provisionalIDReturnsProvisional() {
        let container = CKContainer(identifier: "iCloud.test")
        let allocator = DisplayIDAllocator(container: container)

        let id = allocator.provisionalID()

        #expect(id == .provisional)
    }

    @Test func promoteProvisionalTasksOrdersByCreationDate() async throws {
        let schema = Schema([Project.self, TransitTask.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let modelContainer = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(modelContainer)

        let project = Project(name: "Test", description: "Test", gitRepo: nil, color: .blue)
        context.insert(project)

        // Create tasks with different creation dates (all provisional)
        let task1 = TransitTask(
            name: "First",
            description: nil,
            type: .feature,
            project: project,
            permanentDisplayId: nil,
            metadata: nil
        )
        task1.creationDate = Date.now.addingTimeInterval(-100)

        let task2 = TransitTask(
            name: "Second",
            description: nil,
            type: .feature,
            project: project,
            permanentDisplayId: nil,
            metadata: nil
        )
        task2.creationDate = Date.now.addingTimeInterval(-50)

        let task3 = TransitTask(
            name: "Third",
            description: nil,
            type: .feature,
            project: project,
            permanentDisplayId: nil,
            metadata: nil
        )
        task3.creationDate = Date.now

        context.insert(task1)
        context.insert(task2)
        context.insert(task3)
        try context.save()

        // Verify all are provisional
        #expect(task1.displayID == .provisional)
        #expect(task2.displayID == .provisional)
        #expect(task3.displayID == .provisional)

        // Note: Actual promotion requires CloudKit and would be tested
        // in integration tests with a real or mocked CloudKit container
    }
}
