import Foundation
import SwiftData
import Testing
@testable import Transit

/// Regression tests for T-1607: visual App Entity queries must distinguish a
/// storage fetch failure from a valid empty result.
@MainActor @Suite(.serialized)
struct EntityQueryFetchFailureTests {
    private struct FetchFailure: Swift.Error {}

    private struct FailingProjectFetcher: ProjectFetching {
        func fetchAllProjects(sortedByName: Bool) throws -> [Project] {
            throw FetchFailure()
        }
    }

    private struct FailingTaskFetcher: TaskFetching {
        func fetchAllTasks() throws -> [TransitTask] {
            throw FetchFailure()
        }
    }

    private struct Services {
        let testContainer: TestModelContainer
        let project: ProjectService
        let task: TaskService
    }

    private func makeServices() throws -> Services {
        let testContainer = try TestModelContainer()
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore())
        return Services(
            testContainer: testContainer,
            project: ProjectService(modelContext: testContainer.context),
            task: TaskService(modelContext: testContainer.context, displayIDAllocator: allocator)
        )
    }

    @Test func projectEntitiesForIdentifiersPropagatesFetchFailure() throws {
        let services = try makeServices()

        #expect(throws: FetchFailure.self) {
            _ = try ProjectEntityQuery.entities(
                for: [UUID().uuidString],
                projectService: services.project,
                projectFetcher: FailingProjectFetcher()
            )
        }
    }

    @Test func projectSuggestedEntitiesPropagatesFetchFailure() throws {
        let services = try makeServices()

        #expect(throws: FetchFailure.self) {
            _ = try ProjectEntityQuery.suggestedEntities(
                projectService: services.project,
                projectFetcher: FailingProjectFetcher()
            )
        }
    }

    @Test func taskEntitiesForIdentifiersPropagatesFetchFailure() throws {
        let services = try makeServices()

        #expect(throws: FetchFailure.self) {
            _ = try TaskEntityQuery.entities(
                for: [UUID().uuidString],
                taskService: services.task,
                taskFetcher: FailingTaskFetcher()
            )
        }
    }

    @Test func taskSuggestedEntitiesPropagatesFetchFailure() throws {
        let services = try makeServices()

        #expect(throws: FetchFailure.self) {
            _ = try TaskEntityQuery.suggestedEntities(
                taskService: services.task,
                taskFetcher: FailingTaskFetcher()
            )
        }
    }

    @Test func taskCreationResultEntitiesForIdentifiersPropagatesFetchFailure() throws {
        let services = try makeServices()

        #expect(throws: FetchFailure.self) {
            _ = try TaskCreationResultQuery.entities(
                for: [UUID().uuidString],
                taskService: services.task,
                taskFetcher: FailingTaskFetcher()
            )
        }
    }

    @Test func taskCreationResultSuggestedEntitiesPropagatesFetchFailure() throws {
        let services = try makeServices()

        #expect(throws: FetchFailure.self) {
            _ = try TaskCreationResultQuery.suggestedEntities(
                taskService: services.task,
                taskFetcher: FailingTaskFetcher()
            )
        }
    }
}
