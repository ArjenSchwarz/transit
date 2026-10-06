import Foundation

nonisolated struct ConsolidationSelectionFailure: Error, Sendable {
    struct Diagnostic: Codable, Equatable, Sendable {
        let taskId: UUID
        let reason: String
        var json: [String: String] { ["taskId": taskId.uuidString, "reason": reason] }
    }
    let diagnostics: [Diagnostic]
    init(_ id: UUID, _ reason: String) { diagnostics = [.init(taskId: id, reason: reason)] }
    var code: String { "CONSOLIDATION_SELECTION_INVALID" }
    var message: String { "Selected consolidation identities cannot be used; inspect diagnostics" }
}
