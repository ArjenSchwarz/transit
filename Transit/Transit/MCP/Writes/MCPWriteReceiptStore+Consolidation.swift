import Foundation

extension MCPWriteReceiptStore {
    func validateUndoTerminal(_ envelope: [String: Any], id: UUID, request: [String: Any]) throws {
        guard (request["operationId"] as? String).flatMap(UUID.init(uuidString:)) == id else {
            throw Error.inconsistentReceipt
        }
        if envelope["alreadyReversed"] != nil { try validateAlreadyReversed(envelope, id: id) } else {
            try validateConsolidation(envelope, id: id)
            try validateConsolidationHistory(envelope, id: id, requiresReversal: true)
        }
    }

    func validateAlreadyReversed(_ envelope: [String: Any], id: UUID) throws {
        guard let reversed = envelope["alreadyReversed"], try MCPCanonicalJSON.encode(reversed) == "true",
              (envelope["operationId"] as? String).flatMap(UUID.init(uuidString:)) == id,
              let available = envelope["undoAvailable"], try MCPCanonicalJSON.encode(available) == "false",
              envelope["undoUnavailableReason"] as? String == "already_reversed",
              let reason = envelope["reason"] as? String, !reason.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw Error.inconsistentReceipt
        }
        try validateConsolidationHistory(envelope, id: id, requiresReversal: true)
    }

    func validateConsolidationHistory(_ envelope: [String: Any], id: UUID, requiresReversal: Bool) throws {
        guard let raw = envelope["history"] else {
            if requiresReversal { throw Error.inconsistentReceipt }
            return // Historical foundation receipts keep their original validated bytes.
        }
        let history = try JSONDecoder().decode(ConsolidationHistoryProjection.self,
            from: JSONSerialization.data(withJSONObject: raw))
        guard history.operationId == id, history.apply.operationId == id,
              history.operationRevision == envelope["operationRevision"] as? String,
              history.apply.reason == envelope["reason"] as? String,
              let available = envelope["undoAvailable"],
              try MCPCanonicalJSON.encode(available) == (history.undoAvailable ? "true" : "false"),
              history.undoUnavailableReason == envelope["undoUnavailableReason"] as? String else {
            throw Error.inconsistentReceipt
        }
        try TaskConsolidationHistoryCodec.validate(history.apply)
        if requiresReversal {
            guard let reversal = history.reversal, let reversalId = history.reversalId, reversalId != id,
                  reversal.kind == "undo", reversal.operationId == id,
                  (envelope["reversalId"] as? String).flatMap(UUID.init(uuidString:)) == reversalId else {
                throw Error.inconsistentReceipt
            }
            let apply = try event(history.apply, id: id, physical: Data([0]))
            let undo = try event(reversal, id: reversalId, physical: Data([1]))
            _ = try TaskConsolidationHistoryCodec.history([apply, undo], operationId: id)
        } else if history.reversal != nil || history.reversalId != nil { throw Error.inconsistentReceipt }
        if let participants = envelope["participants"] as? [[String: Any]] {
            let ids = participants.compactMap { ($0["taskId"] as? String).flatMap(UUID.init(uuidString:)) }
            guard Set(ids) == Set([history.apply.survivorTaskId] + history.apply.candidateTaskIds) else {
                throw Error.inconsistentReceipt
            }
        }
    }

    private func event(_ payload: TaskConsolidationPayload, id: UUID, physical: Data) throws
        -> TaskConsolidationEventValue {
        let slots = payload.candidateTaskIds.map(Optional.some)
            + Array(repeating: nil, count: 5 - payload.candidateTaskIds.count)
        return TaskConsolidationEventValue(physicalKey: physical, id: id, operationId: payload.operationId,
            kind: payload.kind, createdAt: "0", originScopeId: "validated-terminal-envelope",
            survivorTaskId: payload.survivorTaskId, candidateSlots: slots,
            payloadJSON: try TaskConsolidationHistoryCodec.encode(payload))
    }
}
