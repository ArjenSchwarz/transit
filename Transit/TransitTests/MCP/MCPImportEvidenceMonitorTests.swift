#if os(macOS)
import Foundation
import Testing
@testable import Transit

struct MCPImportEvidenceMonitorTests {
    @Test func relevantSuccessNeedsCaptureProofAndPreservesLastSuccess() {
        let now = ContinuousClock.now
        let date = Date(timeIntervalSince1970: 100)
        let monitor = MCPImportEvidenceMonitor(syncActive: true, storeIdentifier: "store")
        let id = UUID()
        monitor.receive(.init(id: id, storeIdentifier: "store", kind: .import,
                              startDate: date, endDate: date, succeeded: true),
                        observedAt: date, monotonicNow: now)
        let state = monitor.snapshot()
        #expect(state.generation == 1)
        #expect(monitor.freshness(state, proof: nil, asOf: date, now: now).assessment == .unknown)
        let proof = MCPImportCaptureProof(storeIdentifier: "store", visibleImportIDs: [id])
        #expect(monitor.freshness(state, proof: proof, asOf: date, now: now).assessment == .recentImport)
        monitor.receive(.init(id: UUID(), storeIdentifier: "store", kind: .import,
                              startDate: date, endDate: date, succeeded: false),
                        observedAt: date, monotonicNow: now)
        #expect(monitor.snapshot().lastSuccess?.event.id == id)
    }

    @Test func unrelatedEventsAndStoppedCallbacksCannotChangeGeneration() {
        let monitor = MCPImportEvidenceMonitor(syncActive: true, storeIdentifier: "store")
        let date = Date()
        for kind in [MCPImportEvent.Kind.setup, .export, .import] {
            monitor.receive(.init(id: UUID(), storeIdentifier: "other", kind: kind,
                                  startDate: date, endDate: date, succeeded: true))
        }
        #expect(monitor.snapshot().generation == 0)
        monitor.stop()
        monitor.receive(.init(id: UUID(), storeIdentifier: "store", kind: .import,
                              startDate: date, endDate: date, succeeded: true))
        #expect(monitor.snapshot().generation == 0)
    }

    @Test func recencyUsesBothMonotonicAndWallClockBoundaries() {
        let now = ContinuousClock.now
        let date = Date(timeIntervalSince1970: 100)
        let id = UUID()
        let monitor = MCPImportEvidenceMonitor(syncActive: true, storeIdentifier: "store")
        monitor.receive(.init(id: id, storeIdentifier: "store", kind: .import,
                              startDate: date, endDate: date, succeeded: true),
                        observedAt: date, monotonicNow: now)
        let proof = MCPImportCaptureProof(storeIdentifier: "store", visibleImportIDs: [id])
        let snapshot = monitor.snapshot()
        #expect(monitor.freshness(snapshot, proof: proof, asOf: date.addingTimeInterval(30),
                                  now: now.advanced(by: .seconds(30))).assessment == .recentImport)
        #expect(monitor.freshness(snapshot, proof: proof, asOf: date.addingTimeInterval(31),
                                  now: now.advanced(by: .seconds(31))).assessment == .stale)
        #expect(monitor.freshness(snapshot, proof: proof, asOf: date.addingTimeInterval(-1),
                                  now: now).assessment == .unknown)
    }

    @Test func malformedImportAndClockJumpsFailClosed() {
        let date = Date(timeIntervalSince1970: 100)
        let now = ContinuousClock.now
        let id = UUID()
        let monitor = MCPImportEvidenceMonitor(syncActive: true, storeIdentifier: "store")
        monitor.receive(.init(id: id, storeIdentifier: "store", kind: .import,
                              startDate: date, endDate: date.addingTimeInterval(1), succeeded: true),
                        observedAt: date, monotonicNow: now)
        #expect(monitor.snapshot().lastSuccess == nil)
        monitor.receive(.init(id: id, storeIdentifier: "store", kind: .import,
                              startDate: date, endDate: date, succeeded: true),
                        observedAt: date, monotonicNow: now)
        let snapshot = monitor.snapshot()
        let proof = MCPImportCaptureProof(storeIdentifier: "store", visibleImportIDs: [id])
        #expect(monitor.freshness(snapshot, proof: proof, asOf: date.addingTimeInterval(2),
                                  now: now.advanced(by: .seconds(20))).assessment == .unknown)
        let wrongStore = MCPImportCaptureProof(storeIdentifier: "other", visibleImportIDs: [id])
        #expect(monitor.freshness(snapshot, proof: wrongStore, asOf: date, now: now).lastImportedAt == nil)
        let inactive = MCPImportEvidenceMonitor(syncActive: false, storeIdentifier: "store")
        #expect(inactive.freshness(inactive.snapshot(), proof: proof, asOf: date,
                                   now: now).assessment == .notApplicable)
    }

    @Test func concurrentCallbackCopiesAreSerializedBeforeFenceRead() {
        let date = Date()
        let monitor = MCPImportEvidenceMonitor(syncActive: true, storeIdentifier: "store")
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            monitor.receive(.init(id: UUID(), storeIdentifier: "store", kind: .import,
                                  startDate: date, endDate: date, succeeded: true))
        }
        #expect(monitor.snapshot().generation == 100)
    }

}
#endif
