//
//  StatusEngineTests.swift
//  TransitTests
//
//  Tests for StatusEngine transition logic.
//

import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Transit

@MainActor
struct StatusEngineTests {
    private func makeTestTask() -> TransitTask {
        let schema = Schema([Project.self, TransitTask.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: [config]) else {
            fatalError("Failed to create test container")
        }
        let context = ModelContext(container)

        let project = Project(name: "Test", description: "Test", gitRepo: nil, color: .blue)
        context.insert(project)

        return TransitTask(
            name: "Test Task",
            description: nil,
            type: .feature,
            project: project,
            permanentDisplayId: 1,
            metadata: nil
        )
    }

    // MARK: - Initialize New Task Tests

    @Test func initializeNewTaskSetsIdeaStatus() {
        let task = makeTestTask()
        let now = Date.now

        StatusEngine.initializeNewTask(task, now: now)

        #expect(task.status == .idea)
        #expect(task.creationDate == now)
        #expect(task.lastStatusChangeDate == now)
    }

    // MARK: - Transition Tests

    @Test func transitionUpdatesStatus() {
        let task = makeTestTask()
        StatusEngine.initializeNewTask(task)

        StatusEngine.applyTransition(task: task, to: .planning)

        #expect(task.status == .planning)
    }

    @Test func transitionUpdatesLastStatusChangeDate() {
        let task = makeTestTask()
        let initialTime = Date.now
        StatusEngine.initializeNewTask(task, now: initialTime)

        let transitionTime = initialTime.addingTimeInterval(60)
        StatusEngine.applyTransition(task: task, to: .spec, now: transitionTime)

        #expect(task.lastStatusChangeDate == transitionTime)
    }

    @Test func transitionToDoneSetsCompletionDate() {
        let task = makeTestTask()
        StatusEngine.initializeNewTask(task)
        let completionTime = Date.now

        StatusEngine.applyTransition(task: task, to: .done, now: completionTime)

        #expect(task.completionDate == completionTime)
    }

    @Test func transitionToAbandonedSetsCompletionDate() {
        let task = makeTestTask()
        StatusEngine.initializeNewTask(task)
        let completionTime = Date.now

        StatusEngine.applyTransition(task: task, to: .abandoned, now: completionTime)

        #expect(task.completionDate == completionTime)
    }

    @Test func transitionFromDoneClearsCompletionDate() {
        let task = makeTestTask()
        StatusEngine.initializeNewTask(task)

        // Move to done
        StatusEngine.applyTransition(task: task, to: .done)
        #expect(task.completionDate != nil)

        // Move back to non-terminal
        StatusEngine.applyTransition(task: task, to: .inProgress)
        #expect(task.completionDate == nil)
    }

    @Test func transitionFromAbandonedClearsCompletionDate() {
        let task = makeTestTask()
        StatusEngine.initializeNewTask(task)

        // Move to abandoned
        StatusEngine.applyTransition(task: task, to: .abandoned)
        #expect(task.completionDate != nil)

        // Restore to idea
        StatusEngine.applyTransition(task: task, to: .idea)
        #expect(task.completionDate == nil)
    }

    @Test func transitionBetweenNonTerminalDoesNotSetCompletionDate() {
        let task = makeTestTask()
        StatusEngine.initializeNewTask(task)

        StatusEngine.applyTransition(task: task, to: .planning)
        #expect(task.completionDate == nil)

        StatusEngine.applyTransition(task: task, to: .spec)
        #expect(task.completionDate == nil)

        StatusEngine.applyTransition(task: task, to: .inProgress)
        #expect(task.completionDate == nil)
    }

    @Test func reAbandoningDoneTaskOverwritesCompletionDate() {
        let task = makeTestTask()
        StatusEngine.initializeNewTask(task)

        let doneTime = Date.now
        StatusEngine.applyTransition(task: task, to: .done, now: doneTime)
        #expect(task.completionDate == doneTime)

        let abandonTime = doneTime.addingTimeInterval(60)
        StatusEngine.applyTransition(task: task, to: .abandoned, now: abandonTime)
        #expect(task.completionDate == abandonTime)
    }

    // MARK: - Property-Based Tests (Invariants)

    @Test func completionDateInvariant() {
        let task = makeTestTask()
        StatusEngine.initializeNewTask(task)

        // Test all possible transitions
        let allStatuses = TaskStatus.allCases

        for status in allStatuses {
            StatusEngine.applyTransition(task: task, to: status)

            // Invariant: completionDate is non-nil iff status is terminal
            if status.isTerminal {
                #expect(task.completionDate != nil)
            } else {
                #expect(task.completionDate == nil)
            }
        }
    }

    @Test func lastStatusChangeDateMonotonicity() {
        let task = makeTestTask()
        let startTime = Date.now
        StatusEngine.initializeNewTask(task, now: startTime)

        var previousTime = startTime

        // Apply sequence of transitions with increasing timestamps
        let transitions: [TaskStatus] = [.planning, .spec, .inProgress, .done, .idea]
        for (index, status) in transitions.enumerated() {
            let transitionTime = startTime.addingTimeInterval(Double(index + 1) * 60)
            StatusEngine.applyTransition(task: task, to: status, now: transitionTime)

            // Invariant: lastStatusChangeDate is monotonically non-decreasing
            #expect(task.lastStatusChangeDate >= previousTime)
            previousTime = task.lastStatusChangeDate
        }
    }

    @Test func lastStatusChangeDateAlwaysAfterCreation() {
        let task = makeTestTask()
        let creationTime = Date.now
        StatusEngine.initializeNewTask(task, now: creationTime)

        // Apply various transitions
        for status in TaskStatus.allCases {
            let transitionTime = creationTime.addingTimeInterval(Double.random(in: 1...1000))
            StatusEngine.applyTransition(task: task, to: status, now: transitionTime)

            // Invariant: lastStatusChangeDate >= creationDate
            #expect(task.lastStatusChangeDate >= task.creationDate)
        }
    }
}
