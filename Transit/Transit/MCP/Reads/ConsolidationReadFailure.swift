#if os(macOS)
import Foundation

@MainActor enum ConsolidationReadFailure {
    static func prepare(_ error: Error, tool: String) -> (() throws -> MCPPreparedToolRead)? {
        let code: String, message: String
        var diagnostics: [[String: String]]?
        switch error {
        case let selection as ConsolidationSelectionFailure:
            code = selection.code; message = selection.message
            diagnostics = selection.diagnostics.map(\.json)
        case ConsolidationPlanningError.invalidInput:
            code = "INVALID_INPUT"; message = "Invalid complete consolidation preview input"
        case ConsolidationPlanningError.reviewUnavailable:
            code = "CONSOLIDATION_REVIEW_UNAVAILABLE"; message = "Local consolidation review is unavailable"
        case is TaskConsolidationHistoryError:
            code = "CONSOLIDATION_HISTORY_UNAVAILABLE"; message = "Complete saved history is unavailable"
        case is ConsolidationPlanningError:
            code = "CONSOLIDATION_UNAVAILABLE"; message = "Complete saved consolidation evidence is unavailable"
        default: return nil
        }
        var value: [String: Any] = ["code": code, "message": message]
        if MCPConsolidationToolDefinitions.previewTools.contains(tool) { value["diagnostics"] = diagnostics }
        let json = IntentHelpers.encodeJSON(["error": value])
        return { try MCPPreparedToolRead(text: json, isError: true) }
    }
}
#endif
