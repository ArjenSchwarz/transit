import Foundation
import SwiftData
import Testing
@testable import Transit

/// Project lookup must distinguish a missing project from an unreadable store.
@MainActor @Suite(.serialized)
struct ProjectLookupFetchFailureTests {

    private struct FetchFailure: Swift.Error {}

    private struct FailingFetcher: ModelFetching {
        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
            throw FetchFailure()
        }
    }

    @Test func findProjectByIDFetchFailureIsNotReportedAsNotFound() throws {
        let context = try TestModelContainer().context
        let service = ProjectService(modelContext: context, fetcher: FailingFetcher())

        let result = service.findProject(id: UUID())

        switch result {
        case .success:
            Issue.record("Expected storage failure")
        case .failure(let error):
            guard case .storageFailure = error else {
                Issue.record("Expected storageFailure but got \(error)")
                return
            }
        }
    }

    @Test func findProjectByNameFetchFailureIsNotReportedAsNotFound() throws {
        let context = try TestModelContainer().context
        let service = ProjectService(modelContext: context, fetcher: FailingFetcher())

        let result = service.findProject(name: "Transit")

        switch result {
        case .success:
            Issue.record("Expected storage failure")
        case .failure(let error):
            guard case .storageFailure = error else {
                Issue.record("Expected storageFailure but got \(error)")
                return
            }
        }
    }
}
