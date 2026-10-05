#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPBatchTaskSafetyTests {
    @Test(arguments: [false, true], [false, true])
    func savedObservationPreservesPendingInsertEditDelete(fetchFails: Bool, sharedAutosave: Bool) throws {
        let fixture = try MCPBatchTaskSafetyFixture()
        // Synchronous only: no run-loop suspension may independently autosave.
        fixture.owner.context.autosaveEnabled = sharedAutosave
        let inserted = try fixture.makePendingEdits()
        let guards = try fixture.guardBytes()
        let persistence = PersistenceAvailability()
        do {
            try MCPBatchSavedReadContext.withContext(
                container: fixture.owner.container, persistence: persistence
            ) { (context: ModelContext) in
                #expect(context !== fixture.owner.context)
                #expect(!context.autosaveEnabled)
                #expect(fixture.owner.context.autosaveEnabled == sharedAutosave)
                if fetchFails { throw MCPBatchTaskSafetyFixture.Fault.injected }
                var descriptor = FetchDescriptor<TransitTask>()
                descriptor.includePendingChanges = false
                let tasks = try context.fetch(descriptor)
                #expect(tasks.first { $0.id == fixture.target.id }?.name == "Saved target")
                #expect(tasks.contains { $0.id == fixture.pendingDeletion.id })
                #expect(!tasks.contains { $0.id == inserted.id })
            }
            #expect(!fetchFails)
        } catch { #expect(fetchFails) }
        try fixture.assertPendingPreserved(
            inserted, savedTargetName: "Saved target", expectedAutosave: sharedAutosave)
        #expect(try fixture.guardBytes() == guards)
        #expect(try fixture.owner.context.fetch(FetchDescriptor<MCPWriteReceipt>()).isEmpty)
        #expect(fixture.saves.isEmpty && fixture.recoveryCalls == 0)
    }

    @Test func fallbackStorageNeverSuppliesSavedEvidence() throws {
        let owner = try TestModelContainer()
        var called = false
        #expect(throws: (any Error).self) {
            try MCPBatchSavedReadContext.withContext(
                container: owner.container, persistence: PersistenceAvailability(isFallbackStorageActive: true)
            ) { _ in called = true }
        }
        #expect(!called)
    }
}

extension MCPBatchTaskSafetyTests {
    @Test(arguments: [false, true])
    func dirtyTerminalReplayPreservesOriginalBytes(rejected: Bool) async throws {
        let fixture = try MCPBatchTaskSafetyFixture()
        let args = try fixture.arguments(name: rejected ? "" : "Committed target")
        let first = await fixture.execute(args)
        #expect(try fixture.decode(first)["outcome"] as? String == (rejected ? "rejected" : "committed"))
        let receipt = try fixture.receipt()
        let receiptText = receipt.resultJSON
        let completion = receipt.completedAt
        let expiry = receipt.expiresAt
        let guards = try fixture.guardBytes()
        let inserted = try fixture.makePendingEdits()
        fixture.resetSpies()
        let replay = await fixture.execute(args)
        #expect(replay.content.first?.text == first.content.first?.text)
        #expect(replay.isError == first.isError)
        #expect(receipt.resultJSON == receiptText && receipt.completedAt == completion && receipt.expiresAt == expiry)
        #expect(try fixture.guardBytes() == guards)
        #expect(fixture.saves.isEmpty && fixture.recoveryCalls == 0 && fixture.identityCalls == 0)
        try fixture.assertPendingPreserved(inserted, savedTargetName: rejected ? "Saved target" : "Committed target")
    }

    @Test(arguments: [false, true])
    func dirtyPayloadMismatchChecksRetainedBindingBeforeLiveIdentity(malformedReceipt: Bool) async throws {
        let fixture = try MCPBatchTaskSafetyFixture()
        var args = try fixture.arguments()
        _ = await fixture.execute(args)
        if malformedReceipt {
            try fixture.receipt().resultJSON = "{unreadable"
            try fixture.owner.context.save()
        }
        let guards = try fixture.guardBytes()
        let inserted = try fixture.makePendingEdits()
        args["name"] = "Changed arguments"
        fixture.resetSpies()
        let result = try fixture.decode(await fixture.execute(args, fetchFailure: true))
        #expect((result["error"] as? [String: Any])?["code"] as? String == "IDEMPOTENCY_KEY_REUSED")
        #expect(fixture.saves.isEmpty && fixture.recoveryCalls == 0 && fixture.identityCalls == 0)
        #expect(try fixture.guardBytes() == guards)
        try fixture.assertPendingPreserved(inserted, savedTargetName: "Committed target")
    }

    @Test(arguments: [false, true])
    func dirtyMissingOrInconsistentSidecarDoesNotRepair(inconsistent: Bool) async throws {
        let fixture = try MCPBatchTaskSafetyFixture()
        let args = try fixture.arguments()
        let first = await fixture.execute(args)
        let file = try #require(fixture.guardFiles().first)
        if inconsistent {
            var binding = try JSONDecoder().decode(MCPLocalReservation.self, from: Data(contentsOf: file))
            binding.receiptID = UUID()
            try JSONEncoder().encode(binding).write(to: file)
        } else { try FileManager.default.removeItem(at: file) }
        let guards = try fixture.guardBytes()
        let inserted = try fixture.makePendingEdits()
        fixture.resetSpies()
        let result = await fixture.execute(args)
        if inconsistent {
            #expect(try fixture.decode(result)["outcome"] as? String == "uncertain")
        } else { #expect(result.content.first?.text == first.content.first?.text) }
        #expect(try fixture.guardBytes() == guards)
        #expect(fixture.saves.isEmpty && fixture.recoveryCalls == 0 && fixture.identityCalls == 0)
        try fixture.assertPendingPreserved(inserted, savedTargetName: "Committed target")
    }

    @Test(arguments: ["new", "missing", "expired", "unresolved", "malformed"])
    func dirtyUnestablishedEvidenceStopsWithoutRecovery(kind: String) async throws {
        let fixture = try MCPBatchTaskSafetyFixture()
        let args = try fixture.arguments()
        if kind != "new" {
            _ = await fixture.execute(args)
            let receipt = try fixture.receipt()
            if kind == "missing" { fixture.owner.context.delete(receipt) }
            if kind == "expired" {
                let file = try #require(fixture.guardFiles().first)
                var binding = try JSONDecoder().decode(MCPLocalReservation.self, from: Data(contentsOf: file))
                binding.expiresAt = fixture.clock.addingTimeInterval(-1)
                try JSONEncoder().encode(binding).write(to: file)
                fixture.owner.context.delete(receipt)
            }
            if kind == "unresolved" {
                receipt.stateRawValue = "accepted"
                receipt.resultJSON = nil
                receipt.resultIsError = nil
                receipt.completedAt = nil
                receipt.expiresAt = nil
                let file = try #require(fixture.guardFiles().first)
                var binding = try JSONDecoder().decode(MCPLocalReservation.self, from: Data(contentsOf: file))
                binding.expiresAt = nil
                try JSONEncoder().encode(binding).write(to: file)
            }
            if kind == "malformed" { receipt.resultJSON = "{unreadable" }
            try fixture.owner.context.save()
        }
        let guards = try fixture.guardBytes()
        let inserted = try fixture.makePendingEdits()
        fixture.resetSpies()
        let result = try fixture.decode(await fixture.execute(args))
        #expect(result["outcome"] as? String == "uncertain")
        #expect(result["retryAction"] as? String == "reconcile")
        #expect(try fixture.guardBytes() == guards)
        #expect(fixture.saves.isEmpty && fixture.recoveryCalls == 0 && fixture.identityCalls == 0)
        try fixture.assertPendingPreserved(
            inserted, savedTargetName: kind == "new" ? "Saved target" : "Committed target")
    }

    @Test(arguments: ["success", "error", "cancelled"])
    func editsDuringPreparationPreserveAcceptedBinding(continuation: String) async throws {
        let fixture = try MCPBatchTaskSafetyFixture()
        let gate = MCPBatchSafetyPreparationGate()
        fixture.installCoordinator(preparation: { _ in
            await gate.park()
            if continuation == "error" { throw MCPBatchTaskSafetyFixture.Fault.injected }
        })
        let args = try fixture.arguments()
        let running = Task { await fixture.execute(args) }
        guard await gate.waitForStart() else {
            await gate.release()
            _ = await running.value
            Issue.record("Expected accepted preparation to suspend")
            return
        }
        let guards = try fixture.guardBytes()
        let inserted = try fixture.makePendingEdits()
        fixture.resetSpies()
        if continuation == "cancelled" { running.cancel() }
        await gate.release()
        let result = try fixture.decode(await running.value)
        #expect(result["outcome"] as? String == "uncertain")
        #expect(result["accepted"] as? Bool == true)
        #expect(result["retryAction"] as? String == "reconcile")
        #expect(try fixture.guardBytes() == guards)
        #expect(fixture.saves.isEmpty && fixture.recoveryCalls == 0 && fixture.identityCalls == 0)
        try fixture.assertPendingPreserved(inserted, savedTargetName: "Saved target")
        let durableOwner = try MCPBatchTaskSafetyFixture.diskOwner(at: fixture.storeURL)
        let receipt = try #require(durableOwner.context.fetch(FetchDescriptor<MCPWriteReceipt>()).first)
        #expect(receipt.stateRawValue == "accepted" && receipt.resultJSON == nil)
    }

    @Test func activeKeyResponseDoesNotFlushConcurrentUIEdits() async throws {
        let fixture = try MCPBatchTaskSafetyFixture()
        let gate = MCPBatchSafetyPreparationGate()
        fixture.installCoordinator(preparation: { _ in await gate.park() })
        let args = try fixture.arguments()
        let running = Task { await fixture.execute(args) }
        guard await gate.waitForStart() else {
            await gate.release()
            _ = await running.value
            Issue.record("Expected active key")
            return
        }
        let inserted = try fixture.makePendingEdits()
        let guards = try fixture.guardBytes()
        fixture.resetSpies()
        let active = try fixture.decode(await fixture.execute(args))
        #expect(active["outcome"] as? String == "in_progress")
        var different = args
        different["name"] = "Different"
        let mismatch = try fixture.decode(await fixture.execute(different))
        #expect((mismatch["error"] as? [String: Any])?["code"] as? String == "IDEMPOTENCY_KEY_REUSED")
        await gate.release()
        #expect(try fixture.decode(await running.value)["outcome"] as? String == "uncertain")
        #expect(fixture.saves.isEmpty && fixture.recoveryCalls == 0 && fixture.identityCalls == 0)
        #expect(try fixture.guardBytes() == guards)
        try fixture.assertPendingPreserved(inserted, savedTargetName: "Saved target")
    }

    @Test(arguments: ["missing", "duplicate", "fetchFailure"])
    func preApplyIdentityRejectsNewEffectsAfterPreparation(kind: String) async throws {
        let fixture = try MCPBatchTaskSafetyFixture()
        let args = try fixture.arguments()
        fixture.installCoordinator(preparation: { [weak fixture] _ in
            guard let fixture else { throw MCPBatchTaskSafetyFixture.Fault.injected }
            if kind == "missing" { fixture.owner.context.delete(fixture.target) }
            if kind == "duplicate" {
                let duplicate = TransitTask(name: "UUID collision", type: .feature,
                                            project: fixture.project, displayID: .permanent(4))
                duplicate.id = fixture.target.id
                fixture.owner.context.insert(duplicate)
            }
            // A peer save precedes the fresh synchronous phase; it is not an
            // impossible UI interleaving inside that phase.
            try fixture.owner.context.save()
        })
        let result = try fixture.decode(await fixture.execute(args, fetchFailure: kind == "fetchFailure"))
        #expect(result["outcome"] as? String == "rejected")
        let code = (result["error"] as? [String: Any])?["code"] as? String
        #expect(code == (kind == "missing" ? "TASK_NOT_FOUND" :
            kind == "duplicate" ? "DUPLICATE_TASK_IDENTIFIER" : "INTERNAL_ERROR"))
        // Missing before preparation is rejected by the original resolver;
        // ambiguity and injected callback failure reach the fresh apply gate.
        #expect(fixture.identityCalls == (kind == "missing" ? 0 : 1))
        let durableOwner = try MCPBatchTaskSafetyFixture.diskOwner(at: fixture.storeURL)
        #expect(try durableOwner.context.fetch(FetchDescriptor<TransitTask>()).allSatisfy {
            $0.name != "Committed target"
        })
    }

    @Test func defaultPreApplyPolicyRejectsMissingSavedIdentity() throws {
        let fixture = try MCPBatchTaskSafetyFixture()
        let command = try MCPWriteCommand.validate(tool: "update_task", arguments: fixture.arguments())
        fixture.owner.context.delete(fixture.target)
        try fixture.owner.context.save()
        do {
            try fixture.policy().validateBeforeApply(command, fixture.owner.context)
            Issue.record("Missing UUID must fail the fresh synchronous callback")
        } catch let failure as MCPWriteFailure {
            #expect(failure.code == "TASK_NOT_FOUND")
        }
        #expect(fixture.identityCalls == 1)
        #expect(fixture.saves.isEmpty && fixture.recoveryCalls == 0)
    }

    @Test(arguments: [false, true])
    func historicalReplayBypassesDeletedOrAmbiguousTarget(duplicate: Bool) async throws {
        let fixture = try MCPBatchTaskSafetyFixture()
        let args = try fixture.arguments()
        let first = await fixture.execute(args)
        if duplicate {
            let collision = TransitTask(name: "Collision", type: .feature,
                                        project: fixture.project, displayID: .permanent(4))
            collision.id = fixture.target.id
            fixture.owner.context.insert(collision)
        } else { fixture.owner.context.delete(fixture.target) }
        try fixture.owner.context.save()
        fixture.resetSpies()
        let replay = await fixture.execute(args, fetchFailure: true)
        #expect(replay.content.first?.text == first.content.first?.text && replay.isError == first.isError)
        #expect(fixture.identityCalls == 0)
    }

    @Test(arguments: ["acceptance", "commit", "rejection"])
    func cleanPhaseFaultsRollbackOnlyTheirOwnStagedChanges(stage: String) async throws {
        let fixture = try MCPBatchTaskSafetyFixture()
        fixture.failingStage = stage == "acceptance" ? .acceptance : stage == "commit" ? .commit : .rejection
        let args = try fixture.arguments(name: stage == "rejection" ? "" : "Committed target")
        let result = try fixture.decode(await fixture.execute(args))
        #expect(result["outcome"] as? String != "committed")
        let durableOwner = try MCPBatchTaskSafetyFixture.diskOwner(at: fixture.storeURL)
        #expect(try durableOwner.context.fetch(FetchDescriptor<TransitTask>()).first {
            $0.id == fixture.target.id
        }?.name == "Saved target")
        // Subsequent UI work must not accidentally persist a failed domain edit.
        fixture.project.name = "Later independently saved UI work"
        try fixture.owner.context.save()
        let afterUI = try MCPBatchTaskSafetyFixture.diskOwner(at: fixture.storeURL)
        #expect(try afterUI.context.fetch(FetchDescriptor<TransitTask>()).first {
            $0.id == fixture.target.id
        }?.name == "Saved target")
    }

    @Test func standaloneNilPolicyRetainsExistingPendingBaselineBehavior() async throws {
        let fixture = try MCPBatchTaskSafetyFixture()
        let args = try fixture.arguments()
        fixture.project.name = "Standalone pending baseline"
        let result = try fixture.decode(await fixture.coordinator.execute(tool: "update_task", arguments: args))
        #expect(result["outcome"] as? String == "committed")
        let durableOwner = try MCPBatchTaskSafetyFixture.diskOwner(at: fixture.storeURL)
        #expect(try durableOwner.context.fetch(FetchDescriptor<Project>()).first?.name == "Standalone pending baseline")
        #expect(fixture.identityCalls == 0)
    }
}
#endif
