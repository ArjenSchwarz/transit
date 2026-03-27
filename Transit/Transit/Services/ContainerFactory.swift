import Foundation
import OSLog
import SwiftData

/// Creates a SwiftData `ModelContainer`, falling back to an in-memory container
/// if the primary store cannot be opened.
enum ContainerFactory {

    /// The result of a container creation attempt.
    struct Result {
        /// A usable container — either the requested one or an in-memory fallback.
        let container: ModelContainer
        /// Non-nil when the primary container failed and the fallback was used.
        let error: (any Error)?
    }

    private static let logger = Logger(subsystem: "me.nore.ig.Transit", category: "ContainerFactory")

    /// Attempts to create a `ModelContainer` with the given configuration.
    /// If that fails, creates an in-memory fallback so the app can still launch.
    static func makeContainer(schema: Schema, configuration: ModelConfiguration) -> Result {
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            return Result(container: container, error: nil)
        } catch {
            logger.error("ModelContainer init failed: \(error.localizedDescription). Falling back to in-memory store.")
            // Fallback: in-memory container so the app remains usable.
            let fallbackConfig = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            // If even the fallback fails, there's nothing we can do — this is a fatal environment issue.
            // swiftlint:disable:next force_try
            let fallback = try! ModelContainer(for: schema, configurations: [fallbackConfig])
            return Result(container: fallback, error: error)
        }
    }
}
