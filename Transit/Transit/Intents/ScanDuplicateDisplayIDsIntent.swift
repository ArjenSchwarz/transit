import AppIntents
import Foundation

/// Scans for tasks and milestones sharing a `permanentDisplayId` and returns the
/// report as a JSON string. Read-only — does not mutate any records.
///
/// Surfaces parity with the `scan_duplicate_display_ids` MCP tool: both invoke
/// `DisplayIDMaintenanceService.scanDuplicates()` and JSONEncoder-encode the same
/// `DuplicateReport` value, so the top-level JSON shape is identical (AC 6.3).
///
/// Per Transit intent convention (AC 6.4) any internal failure is captured as a
/// JSON error payload rather than thrown.
struct ScanDuplicateDisplayIDsIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Transit: Scan Duplicate Display IDs"

    nonisolated(unsafe) static var description = IntentDescription(
        "Scan Transit for tasks and milestones sharing a display ID. Returns a JSON report.",
        categoryName: "Maintenance",
        resultValueName: "Duplicate Report JSON"
    )

    nonisolated(unsafe) static var openAppWhenRun: Bool = false

    @Dependency
    private var maintenanceService: DisplayIDMaintenanceService

    @MainActor
    func perform() async throws -> some ReturnsValue<String> {
        let result = await ScanDuplicateDisplayIDsIntent.execute(
            maintenanceService: maintenanceService
        )
        return .result(value: result)
    }

    // MARK: - Logic (testable without @Dependency)

    /// Runs the scan and encodes the result. Errors are returned as a JSON payload
    /// so callers always parse a valid JSON string (matches the existing intent
    /// convention — see `IntentError.json`).
    @MainActor
    static func execute(
        maintenanceService: DisplayIDMaintenanceService
    ) async -> String {
        do {
            let report = try maintenanceService.scanDuplicates()
            return try encode(report)
        } catch {
            return IntentError.internalError(hint: "Failed to scan duplicates: \(error)").json
        }
    }

    /// Reuses the same JSONEncoder configuration as the MCP dispatch handler so
    /// Intent and MCP outputs share a byte-equal encoding for the same input.
    private static func encode(_ value: some Encodable) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw IntentEncodingError.utf8
        }
        return text
    }

    private enum IntentEncodingError: Swift.Error { case utf8 }
}
