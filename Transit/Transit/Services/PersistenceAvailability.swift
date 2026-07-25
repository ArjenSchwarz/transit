import Foundation

/// Single source of truth for whether Transit's writes reach durable storage.
///
/// When the persistent SwiftData store cannot be opened, `ContainerFactory` falls back to an
/// in-memory `ModelContainer` so the app still launches and stays usable. An interactive user
/// sees the "Unable to Load Data" alert and can decide what to do with that knowledge.
/// Automation callers never see that alert: MCP clients and Shortcuts/CLI App Intents received
/// ordinary success responses for writes that vanish on the next launch, which is
/// indistinguishable from a durable write [T-1818, T-1836].
///
/// `TransitApp` derives this flag from the `ContainerFactory` outcome once at launch. Every
/// mutating automation entry point consults the same flag and refuses to write.
///
/// Reads are deliberately left working. A read cannot destroy data, degraded-mode
/// introspection is useful for diagnosing the problem, and every follow-up action that could
/// act on a stale or empty read is itself blocked by this gate.
@MainActor
final class PersistenceAvailability {

    /// The instance consulted by the MCP and App Intents surfaces at runtime.
    static let shared = PersistenceAvailability()

    /// True when the in-memory fallback container is in use, meaning writes are lost on relaunch.
    private(set) var isFallbackStorageActive: Bool

    /// Hint returned verbatim to automation callers whose mutation was rejected. Kept as a
    /// single stable string so scripted callers can match on it across both surfaces.
    nonisolated static let unavailableHint = """
        Transit could not open its database and is running on temporary in-memory storage. \
        Write operations are rejected because the data would be lost on restart. Restart Transit \
        to retry, and check available device storage if the problem persists.
        """

    init(isFallbackStorageActive: Bool = false) {
        self.isFallbackStorageActive = isFallbackStorageActive
    }

    /// Derives availability from a `ContainerFactory` outcome: a non-nil error means the primary
    /// store failed to open and the in-memory fallback is in use.
    ///
    /// `TransitApp` calls this once at launch on `shared`; tests call it on their own instance with
    /// an injected-failure outcome to reproduce degraded storage without launching the app.
    func update(from outcome: ContainerFactory.ContainerOutcome) {
        isFallbackStorageActive = outcome.error != nil
    }
}
