import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPLocalReservationStoreTests {
    @Test func bindingSurvivesRestartAndUnresolvedNeverExpires() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var store: MCPLocalReservationStore? = try MCPLocalReservationStore(directory: directory)
        let scope = store!.scopeID
        let guardRecord = try store!.reserve(tool: "create_task", key: "key", requestJSON: "{}")
        store = nil
        let reopened = try MCPLocalReservationStore(directory: directory)
        #expect(reopened.scopeID == scope)
        #expect(try reopened.lookup(tool: "create_task", key: "key") == guardRecord)
        #expect(throws: MCPLocalReservationStore.Error.keyReused) {
            try reopened.reserve(tool: "create_task", key: "key", requestJSON: "{\"x\":1}")
        }
        try reopened.removeExpired(now: Date.distantFuture)
        #expect(try reopened.lookup(tool: "create_task", key: "key") != nil)
    }

    @Test func unreadableGuardsFailClosed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var store: MCPLocalReservationStore? = try MCPLocalReservationStore(directory: directory)
        _ = try store!.reserve(tool: "create_task", key: "key", requestJSON: "{}")
        store = nil
        let files = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("guards"),
                                                               includingPropertiesForKeys: nil)
        try Data("corrupted".utf8).write(to: files[0])
        #expect(throws: (any Error).self) { try MCPLocalReservationStore(directory: directory) }
    }

    @Test func terminalExpiryIsFixedAndRepairUsesOriginalDeadline() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MCPLocalReservationStore(directory: directory)
        let guardRecord = try store.reserve(tool: "create_task", key: "key", requestJSON: "{}")
        let expiry = Date(timeIntervalSinceReferenceDate: 604800)
        try store.recordExpiry(guardRecord, expiresAt: expiry)
        try store.recordExpiry(guardRecord, expiresAt: expiry)
        #expect(throws: (any Error).self) {
            try store.recordExpiry(guardRecord, expiresAt: expiry.addingTimeInterval(1))
        }
        try store.removeExpired(now: expiry.addingTimeInterval(-1))
        #expect(try store.lookup(tool: "create_task", key: "key") != nil)
        try store.removeExpired(now: expiry)
        #expect(try store.lookup(tool: "create_task", key: "key") == nil)
    }

    @Test func receiptScopeDuplicateAndUnresolvedCleanup() throws {
        let owner = try TestModelContainer()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let guards = try MCPLocalReservationStore(directory: directory)
        let store = MCPWriteReceiptStore(context: owner.context, scopeID: guards.scopeID)
        let binding = try guards.reserve(tool: "create_task", key: "key", requestJSON: "{}")
        let receipt = try store.insert(binding, acceptedAt: Date(timeIntervalSinceReferenceDate: 0))
        owner.context.insert(MCPWriteReceipt(localScopeID: "another-device", tool: "create_task", key: "key",
                                             requestJSON: "{}", acceptedAt: Date()))
        try owner.context.save()
        #expect(try store.lookup(tool: "create_task", key: "key", durable: true)?.id == receipt.id)
        try store.cleanup(now: Date.distantFuture, reservations: guards)
        #expect(try guards.lookup(tool: "create_task", key: "key") != nil)
        owner.context.delete(receipt)
        try owner.context.save()
        #expect(try store.lookup(tool: "create_task", key: "key", durable: true) == nil)
        #expect(try guards.lookup(tool: "create_task", key: "key") != nil,
                "Missing receipt must preserve the unresolved payload binding")
        _ = try store.insert(binding, acceptedAt: Date())
        owner.context.insert(MCPWriteReceipt(localScopeID: guards.scopeID, tool: "create_task", key: "key",
                                             requestJSON: "{}", acceptedAt: Date()))
        #expect(throws: (any Error).self) { try store.lookup(tool: "create_task", key: "key") }
    }
}
