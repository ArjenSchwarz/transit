import SwiftData
@testable import Transit

/// Provides a shared in-memory ModelContainer for tests. Creating multiple
/// ModelContainer instances for the same schema in the same process causes
/// `loadIssueModelContainer` errors. Using a single shared container avoids
/// this while giving each test a fresh ModelContext.
@MainActor
enum TestModelContainer {
    private static var _container: ModelContainer?

    static var shared: ModelContainer {
        get throws {
            if let container = _container {
                return container
            }
            let schema = Schema([Project.self, TransitTask.self])
            let config = ModelConfiguration(
                "TransitTests",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [config])
            _container = container
            return container
        }
    }

    /// Returns a fresh ModelContext from the shared container. Each test
    /// should use its own context to avoid cross-test state leakage.
    static func newContext() throws -> ModelContext {
        let container = try shared
        return ModelContext(container)
    }
}
