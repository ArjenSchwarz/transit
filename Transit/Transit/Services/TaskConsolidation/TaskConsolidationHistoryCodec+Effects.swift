import Foundation

extension TaskConsolidationHistoryCodec {
    /// Imported history may restore only effects the apply contract can attribute.
    nonisolated static func validateApplyEffects(_ payload: TaskConsolidationPayload) throws {
        guard payload.kind == "apply" else { return }
        for change in payload.changes {
            if change.taskId == payload.survivorTaskId {
                guard Set(change.fields.keys).isSubset(of: ["description", "metadataJSON"]) else {
                    throw TaskConsolidationHistoryError.malformed
                }
            } else {
                guard Set(change.fields.keys).isSubset(of:
                    ["statusRawValue", "lastStatusChangeDate", "completionDate"]),
                      let status = change.fields["statusRawValue"], let before = status.before,
                      !["done", "abandoned"].contains(before), status.after == "abandoned" else {
                    throw TaskConsolidationHistoryError.malformed
                }
                if let completion = change.fields["completionDate"] {
                    guard let after = completion.after,
                          change.fields["lastStatusChangeDate"].map({ $0.after == after }) ?? true else {
                        throw TaskConsolidationHistoryError.malformed
                    }
                }
            }
        }
    }
}
