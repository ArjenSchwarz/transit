#if os(macOS)
// Private retry state and its synchronous commit/recovery phases stay together.
// swiftlint:disable file_length
import Foundation
import SwiftData

@MainActor final class MCPWriteCoordinator {
    enum SaveStage { case baseline, acceptance, commit, rejection, cleanup }
    private enum Acceptance {
        case result(MCPToolResult)
        case ready(MCPLocalReservation, MCPWriteReceipt)
    }
    private let services: MCPWriteCommandServices
    private let clock: @MainActor () -> Date
    private let save: @MainActor (ModelContext, SaveStage) throws -> Void
    private let encode: @MainActor ([String: Any]) throws -> String
    private let preparationHook: @MainActor (MCPWriteCommand) async throws -> Void
    private let recoveryHook: @MainActor () throws -> Void
    private let persistence: PersistenceAvailability
    private let reservations: MCPLocalReservationStore?
    private let receipts: MCPWriteReceiptStore?
    private let startupFailure: MCPWriteFailure?
    private var active: [String: String] = [:]
    init(
        services: MCPWriteCommandServices, sidecarDirectory: URL,
        persistence: PersistenceAvailability? = nil,
        clock: @escaping @MainActor () -> Date = Date.init,
        save: @escaping @MainActor (ModelContext, SaveStage) throws -> Void = { context, _ in try context.save() },
        encode: @escaping @MainActor ([String: Any]) throws -> String = MCPWriteOutcome.encode,
        preparationHook: @escaping @MainActor (MCPWriteCommand) async throws -> Void = { _ in },
        recoveryHook: @escaping @MainActor () throws -> Void = {}
    ) {
        self.services = services
        let persistence = persistence ?? .shared
        self.persistence = persistence
        self.clock = clock
        self.save = save
        self.encode = encode
        self.preparationHook = preparationHook
        self.recoveryHook = recoveryHook
        if persistence.isFallbackStorageActive {
            reservations = nil
            receipts = nil
            startupFailure = .init("PERSISTENCE_UNAVAILABLE", PersistenceAvailability.unavailableHint)
        } else {
            do {
                let store = try MCPLocalReservationStore(directory: sidecarDirectory)
                reservations = store
                receipts = MCPWriteReceiptStore(context: services.context, scopeID: store.scopeID)
                startupFailure = nil
            } catch MCPLocalReservationStore.Error.storeBusy {
                reservations = nil
                receipts = nil
                startupFailure = .init("STORE_BUSY", "Another process owns this local store")
            } catch {
                reservations = nil
                receipts = nil
                startupFailure = .init("OUTCOME_UNCERTAIN", "Local retry binding storage cannot be read")
            }
        }
    }

    /// Startup maintenance retains the same app-owned lock used by listener restarts.
    func cleanupExpiredOutcomes() throws {
        guard let reservations, let receipts else { return }
        try reservations.withValidatedBindings {
            if services.context.hasChanges { try save(services.context, .baseline) }
            try receipts.cleanup(now: clock(), reservations: reservations)
            if services.context.hasChanges { try save(services.context, .cleanup) }
        }
    }

    func execute(
        tool: String, arguments: [String: Any], batchPolicy: MCPBatchWritePolicy? = nil
    ) async -> MCPToolResult {
        let command: MCPWriteCommand
        do { command = try MCPWriteCommand.validate(tool: tool, arguments: arguments) } catch {
            return MCPWriteOutcome.result(
                MCPWriteOutcome.failure(
                    tool: tool, key: arguments["idempotencyKey"] as? String,
                    failure: MCPWriteFailure.from(error), accepted: false
                ), isError: true)
        }
        if persistence.isFallbackStorageActive {
            return transient(
                command, .init("PERSISTENCE_UNAVAILABLE", PersistenceAvailability.unavailableHint),
                accepted: false, retry: "retry_same_request")
        }
        guard let reservations, let receipts else {
            let failure = startupFailure ?? .init("PERSISTENCE_UNAVAILABLE", "Retry storage unavailable")
            return transient(
                command, failure, accepted: failure.code == "OUTCOME_UNCERTAIN" ? nil : false,
                outcome: failure.code == "OUTCOME_UNCERTAIN" ? "uncertain" : "rejected",
                retry: failure.code == "OUTCOME_UNCERTAIN" ? "reconcile" : "retry_same_request")
        }
        let payload: String
        do { payload = try MCPCanonicalJSON.request(arguments) } catch {
            return transient(
                command, .init("INVALID_INPUT", "Arguments must contain finite JSON values"), accepted: false)
        }
        let namespace = tool + "\u{0000}" + command.key
        if let executing = active[namespace] {
            if executing != payload { return reused(command) }
            return transient(
                command, .init("OPERATION_IN_PROGRESS", "Retry the same request after completion"),
                accepted: true, outcome: "in_progress", retry: "retry_same_request")
        }
        if (batchPolicy != nil || command.hasLinkInput) && services.context.hasChanges {
            return inspectRetainedWhileDirty(
                command, payload: payload, reservations: reservations, receipts: receipts,
                now: clock(), batchPolicy: batchPolicy)
        }
        return await accept(
            command, payload: payload,
            reservations: reservations, receipts: receipts, batchPolicy: batchPolicy)
    }
}

extension MCPWriteCoordinator {
    fileprivate func existingOutcome(
        _ command: MCPWriteCommand, payload: String,
        reservations: MCPLocalReservationStore, receipts: MCPWriteReceiptStore,
        batchPolicy: MCPBatchWritePolicy?
    ) -> MCPToolResult? {
        let tool = command.tool
        do {
            if let guardRecord = try reservations.lookup(tool: tool, key: command.key) {
                if guardRecord.expiresAt.map({ $0 <= clock() }) != true {
                    guard guardRecord.requestJSON == payload else { return reused(command) }
                    return recover(command, guardRecord: guardRecord, batchPolicy: batchPolicy)
                }
            }
            if let receipt = try receipts.lookup(tool: tool, key: command.key, durable: true) {
                if receipt.expiresAt.map({ $0 <= clock() }) != true {
                    guard receipt.requestJSON == payload else { return reused(command) }
                    let repaired = try reservations.reserve(
                        tool: tool, key: command.key, requestJSON: payload,
                        formatVersion: receipt.formatVersion, receiptID: receipt.id)
                    return recover(command, guardRecord: repaired, batchPolicy: batchPolicy)
                }
            }
        } catch {
            // If storage inspection cannot establish prior acceptance, do not
            // describe the key as free or offer a fresh-key retry.
            return transient(
                command, .init("OUTCOME_UNCERTAIN", "Unable to inspect durable retry state"),
                accepted: nil, outcome: "uncertain", retry: "reconcile")
        }
        return nil
    }

    fileprivate func accept(
        _ command: MCPWriteCommand, payload: String,
        reservations: MCPLocalReservationStore, receipts: MCPWriteReceiptStore,
        batchPolicy: MCPBatchWritePolicy?
    ) async -> MCPToolResult {
        let acceptance: Acceptance
        do {
            acceptance = try reservations.withValidatedBindings {
                acceptSynchronously(
                    command, payload: payload, reservations: reservations, receipts: receipts, batchPolicy: batchPolicy)
            }
        } catch {
            return transient(
                command, .init("OUTCOME_UNCERTAIN", "Unable to inspect durable retry state"),
                accepted: nil, outcome: "uncertain", retry: "reconcile")
        }
        switch acceptance {
        case .result(let result): return result
        case .ready(let guardRecord, let receipt):
            let namespace = command.tool + "\u{0000}" + command.key
            active[namespace] = payload
            defer { active.removeValue(forKey: namespace) }
            // The acceptance snapshot is gone before entering any async method.
            return await runAccepted(
                command, guardRecord: guardRecord, receipt: receipt,
                reservations: reservations, batchPolicy: batchPolicy)
        }
    }

    private func acceptSynchronously(
        _ command: MCPWriteCommand, payload: String,
        reservations: MCPLocalReservationStore, receipts: MCPWriteReceiptStore,
        batchPolicy: MCPBatchWritePolicy?
    ) -> Acceptance {
        if (batchPolicy != nil || command.hasLinkInput) && services.context.hasChanges {
            return .result(inspectRetainedWhileDirty(
                command, payload: payload, reservations: reservations, receipts: receipts,
                now: clock(), batchPolicy: batchPolicy))
        }
        let tool = command.tool
        if let existing = existingOutcome(command, payload: payload, reservations: reservations, receipts: receipts,
                                          batchPolicy: batchPolicy) {
            return .result(existing)
        }
        if command.hasLinkInput && batchPolicy?.taskLinkCapability == nil {
            return .result(transient(command,
                .init("PERSISTENCE_UNAVAILABLE", "Typed-link owned plan/apply policy is not installed"),
                accepted: false))
        }
        do {
            if services.context.hasChanges { try save(services.context, .baseline) }
        } catch {
            return .result(transient(
                    command, .init("PERSISTENCE_UNAVAILABLE", "Unable to save existing pending edits"),
                    accepted: false, retry: "retry_same_request"))
        }
        do {
            try receipts.cleanup(now: clock(), reservations: reservations)
            if services.context.hasChanges { try save(services.context, .cleanup) }
        } catch {
            return .result(transient(
                    command, .init("OUTCOME_UNCERTAIN", "Unable to complete retry-state cleanup"),
                    accepted: nil, outcome: "uncertain", retry: "reconcile"))
        }
        let guardRecord: MCPLocalReservation
        do {
            guardRecord = try reservations.reserve(tool: tool, key: command.key, requestJSON: payload)
        } catch {
            return .result(transient(
                    command, .init("OUTCOME_UNCERTAIN", "Unable to confirm durable key acceptance"),
                    accepted: nil, outcome: "uncertain", retry: "reconcile"))
        }
        let receipt: MCPWriteReceipt
        do {
            receipt = try receipts.insert(guardRecord, acceptedAt: clock())
            try save(services.context, .acceptance)
        } catch {
            // No domain command has run. Repair a missing acceptance receipt
            // only as a terminal no-effect rejection, never as a fresh request.
            for model in services.context.insertedModelsArray { services.context.delete(model) }
            services.context.safeRollback()
            return .result(rejectBeforeDomain(
                    command, guardRecord: guardRecord,
                    failure: .init("INTERNAL_ERROR", "Unable to save request acceptance"), batchPolicy: batchPolicy))
        }
        return .ready(guardRecord, receipt)
    }

    fileprivate func runAccepted(
        _ command: MCPWriteCommand, guardRecord: MCPLocalReservation, receipt: MCPWriteReceipt,
        reservations: MCPLocalReservationStore,
        batchPolicy: MCPBatchWritePolicy?
    ) async -> MCPToolResult {
        let prepared: PreparedMCPWrite
        do {
            try await preparationHook(command)
            if (batchPolicy != nil || command.hasLinkInput) && services.context.hasChanges {
                return dirtyUnavailable(command, accepted: true, batchPolicy: batchPolicy)
            }
            prepared = try await command.prepare(using: services)
            try Task.checkCancellation()
        } catch {
            // Return before a rejection phase can save or roll back UI edits.
            if (batchPolicy != nil || command.hasLinkInput) && services.context.hasChanges {
                return dirtyUnavailable(command, accepted: true, batchPolicy: batchPolicy)
            }
            // Validate a fresh scope after suspension, before retaining rejection.
            do {
                return try reservations.withValidatedBindings {
                    try reservations.validateBinding(guardRecord)
                    if services.context.hasChanges { try save(services.context, .baseline) }
                    if batchPolicy?.makeCommitServices != nil {
                        return rejectInOwnedScope(command, guardRecord: guardRecord,
                                                  failure: MCPWriteFailure.from(error), batchPolicy: batchPolicy)
                    }
                    return completeRejection(command, receipt: receipt, failure: MCPWriteFailure.from(error),
                                             guardRecord: guardRecord)
                }
            } catch { return uncertain(command) }
        }
        if (batchPolicy != nil || command.hasLinkInput) && services.context.hasChanges {
            return dirtyUnavailable(command, accepted: true, batchPolicy: batchPolicy)
        }
        do {
            // No snapshot survives preparation. This fresh phase covers baseline,
            // mutation, terminal save, expiry repair, and synchronous recovery.
            return try reservations.withValidatedBindings {
                try reservations.validateBinding(guardRecord)
                if services.context.hasChanges { try save(services.context, .baseline) }
                return commit(
                    command, prepared: prepared, receipt: receipt, guardRecord: guardRecord, batchPolicy: batchPolicy)
            }
        } catch { return uncertain(command) }
    }

    fileprivate func commit(
        _ command: MCPWriteCommand, prepared: PreparedMCPWrite,
        receipt: MCPWriteReceipt, guardRecord: MCPLocalReservation, batchPolicy: MCPBatchWritePolicy?
    ) -> MCPToolResult {
        let scope: MCPWriteCommitScope
        let scopedReceipt: MCPWriteReceipt
        do {
            scope = try MCPWriteCommitScope(shared: services, scopeID: guardRecord.scopeID, policy: batchPolicy)
            scopedReceipt = batchPolicy?.makeCommitServices == nil ? receipt : try scope.receipt(for: guardRecord)
            if let retained = replay(scopedReceipt) { return retained }
        } catch { return uncertain(command) }
        let context = scope.context
        let autosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosave }
        do {
            try batchPolicy?.validateBeforeApply(command, context)
            var envelope = try command.apply(
                prepared, using: scope.services, afterTaskApply: batchPolicy?.afterTaskApply)
            envelope["contractVersion"] = 1
            envelope["tool"] = command.tool
            envelope["idempotencyKey"] = command.key
            envelope["outcome"] = "committed"
            envelope["accepted"] = true
            let result = try stageTerminal(scopedReceipt, envelope: envelope, rejected: false)
            try save(context, .commit)
            // Failed expiry repair never downgrades a committed domain/result.
            try? reservations?.recordExpiry(guardRecord, expiresAt: scopedReceipt.expiresAt!)
            return result
        } catch {
            let failure = MCPWriteFailure.from(error)
            for model in context.insertedModelsArray { context.delete(model) }
            context.safeRollback()
            do {
                try recoveryHook()
                guard let durable = try receipts?.lookup(tool: command.tool, key: command.key, durable: true),
                    MCPWriteCommitScope.matches(durable, guardRecord: guardRecord)
                else { return uncertain(command) }
                if let result = replay(durable) { return result }
                // The disk probe establishes that durable accepted means the
                // domain/result transaction did not commit.
                let live = try scope.receipt(for: guardRecord)
                return completeRejection(command, receipt: live, failure: failure,
                                         guardRecord: guardRecord, scope: scope)
            } catch { return uncertain(command) }
        }
    }

    fileprivate func recover(_ command: MCPWriteCommand, guardRecord: MCPLocalReservation,
                             batchPolicy: MCPBatchWritePolicy?) -> MCPToolResult {
        do {
            try recoveryHook()
            guard let receipt = try receipts?.lookup(tool: command.tool, key: command.key, durable: true),
                MCPWriteCommitScope.matches(receipt, guardRecord: guardRecord)
            else {
                return uncertain(command)
            }
            if let result = replay(receipt) {
                if let expiry = receipt.expiresAt {
                    try? reservations?.recordExpiry(guardRecord, expiresAt: expiry)
                }
                return result
            }
            if batchPolicy?.makeCommitServices != nil {
                return rejectInOwnedScope(command, guardRecord: guardRecord,
                    failure: .init("INTERRUPTED_BEFORE_COMMIT", "Accepted operation did not commit"),
                    batchPolicy: batchPolicy)
            }
            guard let live = try receipts?.lookup(tool: command.tool, key: command.key) else {
                return uncertain(command)
            }
            if services.context.hasChanges { try save(services.context, .baseline) }
            return completeRejection(
                command, receipt: live,
                failure: .init("INTERRUPTED_BEFORE_COMMIT", "Accepted operation did not commit"),
                guardRecord: guardRecord)
        } catch { return uncertain(command) }
    }

    fileprivate func rejectBeforeDomain(
        _ command: MCPWriteCommand, guardRecord: MCPLocalReservation,
        failure: MCPWriteFailure, batchPolicy: MCPBatchWritePolicy?
    ) -> MCPToolResult {
        do {
            try recoveryHook()
            if let durable = try receipts?.lookup(tool: command.tool, key: command.key, durable: true) {
                guard MCPWriteCommitScope.matches(durable, guardRecord: guardRecord) else { return uncertain(command) }
                if let result = replay(durable) { return result }
            }
            if batchPolicy?.makeCommitServices != nil {
                let scope = try MCPWriteCommitScope(shared: services, scopeID: guardRecord.scopeID, policy: batchPolicy)
                let live: MCPWriteReceipt
                if try scope.receipts.lookup(tool: command.tool, key: command.key) != nil {
                    live = try scope.receipt(for: guardRecord)
                } else {
                    // This branch is reached only after acceptance save failed,
                    // before preparation/domain apply; genuine absence is proven.
                    live = try scope.receipts.insert(guardRecord, acceptedAt: clock())
                }
                return completeRejection(command, receipt: live, failure: failure,
                                         guardRecord: guardRecord, scope: scope)
            }
            guard let receipts else { return uncertain(command) }
            let live =
                try receipts.lookup(tool: command.tool, key: command.key)
                ?? receipts.insert(guardRecord, acceptedAt: clock())
            return completeRejection(command, receipt: live, failure: failure, guardRecord: guardRecord)
        } catch { return uncertain(command) }
    }

    fileprivate func completeRejection(
        _ command: MCPWriteCommand, receipt: MCPWriteReceipt,
        failure: MCPWriteFailure, guardRecord: MCPLocalReservation, scope: MCPWriteCommitScope? = nil
    ) -> MCPToolResult {
        guard MCPWriteCommitScope.matches(receipt, guardRecord: guardRecord) else { return uncertain(command) }
        let envelope = MCPWriteOutcome.failure(
            tool: command.tool, key: command.key, failure: failure, accepted: true)
        let context = scope?.context ?? services.context
        do {
            let result = try stageTerminal(receipt, envelope: envelope, rejected: true)
            try save(context, .rejection)
            if let binding = try? reservations?.lookup(tool: command.tool, key: command.key),
                let expiry = receipt.expiresAt {
                try? reservations?.recordExpiry(binding, expiresAt: expiry)
            }
            return result
        } catch {
            for model in context.insertedModelsArray { context.delete(model) }
            context.safeRollback()
            do {
                try recoveryHook()
                if let durable = try receipts?.lookup(tool: command.tool, key: command.key, durable: true),
                    MCPWriteCommitScope.matches(durable, guardRecord: guardRecord),
                    let result = replay(durable) {
                    return result
                }
            } catch {}
            return uncertain(command)
        }
    }

    private func rejectInOwnedScope(_ command: MCPWriteCommand, guardRecord: MCPLocalReservation,
                                    failure: MCPWriteFailure, batchPolicy: MCPBatchWritePolicy?) -> MCPToolResult {
        do {
            let scope = try MCPWriteCommitScope(shared: services, scopeID: guardRecord.scopeID, policy: batchPolicy)
            let receipt = try scope.receipt(for: guardRecord)
            if let retained = replay(receipt) { return retained }
            return completeRejection(command, receipt: receipt, failure: failure,
                                     guardRecord: guardRecord, scope: scope)
        } catch { return uncertain(command) }
    }

    fileprivate func stageTerminal(_ receipt: MCPWriteReceipt, envelope: [String: Any], rejected: Bool) throws
        -> MCPToolResult {
        let completed = clock()
        let expiry = completed.addingTimeInterval(604800)
        var envelope = envelope
        envelope["completedAt"] = MCPRecordSnapshot.timestamp(completed)
        envelope["replayExpiresAt"] = MCPRecordSnapshot.timestamp(expiry)
        let json = try encode(envelope)
        receipt.stateRawValue = rejected ? "rejected" : "committed"
        receipt.completedAt = completed
        receipt.expiresAt = expiry
        receipt.resultJSON = json
        receipt.resultIsError = rejected
        return MCPToolResult(content: [.text(json)], isError: rejected ? true : nil)
    }
}
#endif
