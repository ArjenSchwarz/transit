import Foundation
import SwiftData
@testable import Transit

/// Produces `PersistenceAvailability` values derived from real `ContainerFactory` outcomes, so the
/// degraded-storage regression suites exercise the same derivation `TransitApp.init()` performs at
/// launch rather than flipping the flag by hand [T-1818, T-1836].
///
/// The degraded outcome is created **once** for the whole test process. `ContainerFactory`'s
/// fallback builds its `ModelConfiguration` without a name, so every fallback container in a
/// process shares one in-memory store identity; creating them per test would leak data between
/// tests (the reason `TestModelContainer` names its configurations uniquely) and can trip the
/// `try!` in `ContainerFactory`, taking the whole test host down. Data assertions therefore use
/// isolated `TestModelContainer` contexts, and this fixture supplies only the signal.
@MainActor
enum FallbackOutcomeFixture {

    private enum InjectedFailure: Error { case primaryCreationFailed }

    /// Availability derived from a `ContainerFactory` attempt whose primary store failed to open.
    static let degraded: PersistenceAvailability = {
        let availability = PersistenceAvailability()
        availability.update(from: makeOutcome(failPrimaryStore: true))
        return availability
    }()

    /// Availability derived from a successful `ContainerFactory` attempt. Safe to call per test:
    /// the primary store opens, so no shared fallback container is created.
    static func makeHealthy() -> PersistenceAvailability {
        let availability = PersistenceAvailability()
        availability.update(from: makeOutcome(failPrimaryStore: false))
        return availability
    }

    private static func makeOutcome(failPrimaryStore: Bool) -> ContainerFactory.ContainerOutcome {
        let schema = Schema([Project.self, TransitTask.self, Comment.self, Milestone.self, SyncHeartbeat.self])
        let config = ModelConfiguration(
            "FallbackOutcomeFixture-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return ContainerFactory.makeContainer(
            schema: schema, configuration: config
        ) { innerSchema, innerConfig in
            if failPrimaryStore { throw InjectedFailure.primaryCreationFailed }
            return try ModelContainer(for: innerSchema, configurations: [innerConfig])
        }
    }
}
