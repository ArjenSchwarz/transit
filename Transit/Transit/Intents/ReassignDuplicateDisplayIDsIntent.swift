import AppIntents
import Foundation

/// Reassigns fresh display IDs to losers in each duplicate group and returns the
/// run result as a JSON string. Mutating — see `DisplayIDMaintenanceService` for
/// the per-group flow, audit comments, and counter-advance fence.
///
/// Surfaces parity with the `reassign_duplicate_display_ids` MCP tool: both invoke
/// `DisplayIDMaintenanceService.reassignDuplicates()` and JSONEncoder-encode the
/// same `ReassignmentResult` value, so the top-level JSON shape is identical (AC 6.3).
///
/// Per Transit intent convention (AC 6.4) any internal failure is captured as a
/// JSON error payload rather than thrown. Note that group-level and run-level
/// failures from the service are already part of the `ReassignmentResult` envelope
/// (FailureCode + per-type counter-advance warnings); this intent only needs to
/// catch the rare encoding failure.
struct ReassignDuplicateDisplayIDsIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Reassign Duplicate Display IDs"

    nonisolated(unsafe) static var description = IntentDescription(
        "Reassign fresh display IDs to losers in each duplicate group. Returns a JSON result.",
        categoryName: "Maintenance",
        resultValueName: "Reassignment Result JSON"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = false

    @Dependency
    private var maintenanceService: DisplayIDMaintenanceService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = await ReassignDuplicateDisplayIDsIntent.execute(
            maintenanceService: maintenanceService
        )
        return .result(value: result)
    }

    // MARK: - Logic (testable without @Dependency)

    /// Runs the reassignment and encodes the result. The service never throws —
    /// failures land in the result envelope. The only error path here is the
    /// JSON encoding step itself.
    @MainActor
    static func execute(
        maintenanceService: DisplayIDMaintenanceService,
        persistence: PersistenceAvailability = .shared
    ) async -> String {
        // Refuse to write while the in-memory fallback container is active [T-1836]. Reassignment
        // rewrites display IDs and appends audit comments; replaying it after a restart against
        // the real store would be confusing at best.
        if let unavailable = IntentHelpers.fallbackStorageErrorJSON(persistence) { return unavailable }

        let result = await maintenanceService.reassignDuplicates()
        do {
            return try IntentHelpers.encodeAsJSONString(result)
        } catch {
            return IntentError.internalError(
                hint: "Failed to encode reassignment result: \(error.localizedDescription)"
            ).json
        }
    }
}
