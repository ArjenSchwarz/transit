import Foundation
import SwiftData

/// Stages receipts in the shared context; it never saves a domain operation.
@MainActor final class MCPWriteReceiptStore {
    enum Error: Swift.Error { case inconsistentReceipt }
    let scopeID: String
    private let context: ModelContext
    private let container: ModelContainer

    init(context: ModelContext, scopeID: String) {
        self.context = context
        self.container = context.container
        self.scopeID = scopeID
    }

    func lookup(tool: String, key: String, durable: Bool = false) throws -> MCPWriteReceipt? {
        let source = durable ? ModelContext(container) : context
        let scope = scopeID
        let descriptor = FetchDescriptor<MCPWriteReceipt>(predicate: #Predicate {
            $0.localScopeID == scope && $0.tool == tool && $0.key == key
        })
        let receipts = try source.fetch(descriptor)
        guard receipts.count <= 1 else { throw Error.inconsistentReceipt }
        if let receipt = receipts.first { try validate(receipt) }
        return receipts.first
    }

    func insert(_ reservation: MCPLocalReservation, acceptedAt: Date) throws -> MCPWriteReceipt {
        guard reservation.scopeID == scopeID,
              try lookup(tool: reservation.tool, key: reservation.key) == nil else { throw Error.inconsistentReceipt }
        let receipt = MCPWriteReceipt(id: reservation.receiptID, localScopeID: scopeID,
                                      tool: reservation.tool, key: reservation.key,
                                      formatVersion: reservation.formatVersion,
                                      requestJSON: reservation.requestJSON, acceptedAt: acceptedAt)
        context.insert(receipt)
        return receipt
    }

    func validate(_ receipt: MCPWriteReceipt) throws {
        guard receipt.localScopeID == scopeID, receipt.formatVersion == 1,
              !receipt.tool.isEmpty, !receipt.key.isEmpty,
              receipt.acceptedAt.timeIntervalSinceReferenceDate.isFinite,
              let data = receipt.requestJSON.data(using: .utf8),
              let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              try MCPCanonicalJSON.encode(request) == receipt.requestJSON else {
            throw Error.inconsistentReceipt
        }
        if receipt.stateRawValue == "accepted" {
            guard receipt.completedAt == nil, receipt.expiresAt == nil,
                  receipt.resultJSON == nil, receipt.resultIsError == nil else { throw Error.inconsistentReceipt }
        } else {
            guard ["committed", "rejected"].contains(receipt.stateRawValue),
                  let completed = receipt.completedAt, completed.timeIntervalSinceReferenceDate.isFinite,
                  let expiry = receipt.expiresAt, expiry == completed.addingTimeInterval(604800),
                  let result = receipt.resultJSON?.data(using: .utf8),
                  let envelope = try JSONSerialization.jsonObject(with: result) as? [String: Any],
                  envelope["contractVersion"] as? Int == 1,
                  envelope["outcome"] as? String == receipt.stateRawValue,
                  envelope["tool"] as? String == receipt.tool,
                  envelope["idempotencyKey"] as? String == receipt.key,
                  let accepted = envelope["accepted"], try MCPCanonicalJSON.encode(accepted) == "true",
                  receipt.resultIsError == (receipt.stateRawValue == "rejected") else {
                throw Error.inconsistentReceipt
            }
        }
    }

    /// Repair terminal guard deadlines before deleting either side. The caller
    /// saves staged receipt deletions; a remaining receipt can restore its guard.
    func cleanup(now: Date, reservations: MCPLocalReservationStore) throws {
        guard reservations.scopeID == scopeID else { throw Error.inconsistentReceipt }
        let scope = scopeID
        let receipts = try context.fetch(FetchDescriptor<MCPWriteReceipt>(predicate: #Predicate {
            $0.localScopeID == scope
        }))
        for receipt in receipts {
            _ = try lookup(tool: receipt.tool, key: receipt.key)
            guard let expiry = receipt.expiresAt else { continue }
            let binding = try reservations.reserve(tool: receipt.tool, key: receipt.key,
                                                  requestJSON: receipt.requestJSON,
                                                  formatVersion: receipt.formatVersion, receiptID: receipt.id)
            guard binding.receiptID == receipt.id else { throw Error.inconsistentReceipt }
            try reservations.recordExpiry(binding, expiresAt: expiry)
            if expiry <= now { context.delete(receipt) }
        }
        try reservations.removeExpired(now: now)
    }
}
