#if os(macOS)
import Foundation
import Testing
@testable import Transit

struct MCPReadRefreshPolicyTests {
    @Test func skipAndUnavailableDecisions() {
        let empty = MCPImportEvidenceMonitor(syncActive: true, storeIdentifier: "store").snapshot()
        #expect(MCPReadRefreshPolicy.decision(policy: .cached, snapshot: empty,
                                             recent: false, remaining: .seconds(5)) == .skip(.notRequested))
        #expect(MCPReadRefreshPolicy.decision(policy: .refreshIfNeeded, snapshot: empty,
                                             recent: false, remaining: .seconds(5)) == .skip(.unavailable))
        #expect(MCPReadRefreshPolicy.decision(policy: .refreshIfNeeded, snapshot: empty,
                                             recent: true, remaining: .seconds(5)) == .skip(.recentImport))
        #expect(MCPReadRefreshPolicy.parse(nil) == .refreshIfNeeded)
        #expect(MCPReadRefreshPolicy.parse("cached") == .cached)
        #expect(MCPReadRefreshPolicy.parse(1) == nil)
        #expect(MCPReadRefreshPolicy.parse("invalid") == nil)
    }

    @Test func boundedInflightAndInactive() {
        let monitor = MCPImportEvidenceMonitor(syncActive: true, storeIdentifier: "store")
        monitor.receive(.init(id: UUID(), storeIdentifier: "store", kind: .import,
                              startDate: Date(), endDate: nil, succeeded: false))
        let state = monitor.snapshot()
        #expect(MCPReadRefreshPolicy.decision(policy: .refreshIfNeeded, snapshot: state,
                                             recent: false, remaining: .seconds(5),
                                             applicableInFlightIDs: state.inFlight) == .wait(.seconds(2)))
        #expect(MCPReadRefreshPolicy.decision(policy: .refreshIfNeeded, snapshot: state,
                                             recent: false, remaining: .milliseconds(250),
                                             applicableInFlightIDs: state.inFlight) == .wait(.milliseconds(250)))
        #expect(MCPReadRefreshPolicy.decision(policy: .refreshIfNeeded, snapshot: state,
                                             recent: false, remaining: .zero,
                                             applicableInFlightIDs: state.inFlight) == .skip(.timeout))
        let inactive = MCPImportEvidenceMonitor(syncActive: false, storeIdentifier: "store").snapshot()
        #expect(MCPReadRefreshPolicy.decision(policy: .refreshIfNeeded, snapshot: inactive,
                                             recent: true, remaining: .seconds(5)) == .skip(.notRequested))
    }

    @Test func applicabilityAndOutcomePriority() {
        let date = Date()
        let id = UUID()
        let monitor = MCPImportEvidenceMonitor(syncActive: true, storeIdentifier: "store")
        monitor.receive(.init(id: id, storeIdentifier: "store", kind: .import,
                              startDate: date, endDate: nil, succeeded: false))
        let initial = monitor.snapshot()
        #expect(MCPReadRefreshPolicy.decision(policy: .refreshIfNeeded, snapshot: initial,
                                             recent: false, remaining: .seconds(5)) == .skip(.unavailable))
        monitor.receive(.init(id: id, storeIdentifier: "store", kind: .import,
                              startDate: date, endDate: date, succeeded: false))
        let failed = monitor.snapshot()
        #expect(MCPReadRefreshPolicy.outcome(initial: initial, final: failed, proof: nil,
                                            applicableInFlightIDs: [id]) == .failed)
        monitor.receive(.init(id: id, storeIdentifier: "store", kind: .import,
                              startDate: date, endDate: date, succeeded: true))
        let successful = monitor.snapshot()
        let proof = MCPImportCaptureProof(storeIdentifier: "store", visibleImportIDs: [id])
        #expect(MCPReadRefreshPolicy.outcome(initial: initial, final: successful, proof: proof,
                                            applicableInFlightIDs: [id]) == .importObserved)
        #expect(MCPReadRefreshPolicy.outcome(initial: initial, final: successful, proof: nil,
                                            applicableInFlightIDs: [id]) == .failed)
    }

    @Test func waitObservesCompletionWithoutMainActorHop() async throws {
        let date = Date()
        let id = UUID()
        let monitor = MCPImportEvidenceMonitor(syncActive: true, storeIdentifier: "store")
        monitor.receive(.init(id: id, storeIdentifier: "store", kind: .import,
                              startDate: date, endDate: nil, succeeded: false))
        let observation = try monitor.beginObservation(applicableImportIDs: [id])
        defer { observation.close() }
        let initial = monitor.snapshot(observation: observation)
        let final = await MCPReadRefreshPolicy.wait(monitor: monitor, initial: initial,
                                                    duration: .milliseconds(50),
                                                    observation: observation, sleep: { _ in
            monitor.receive(.init(id: id, storeIdentifier: "store", kind: .import,
                                  startDate: date, endDate: date, succeeded: true))
        })
        #expect(final.lastSuccess?.event.id == id)
    }

    @Test func waitStopsAtShortenedDeadline() async throws {
        let monitor = MCPImportEvidenceMonitor(syncActive: true, storeIdentifier: "store")
        monitor.receive(.init(id: UUID(), storeIdentifier: "store", kind: .import,
                              startDate: Date(), endDate: nil, succeeded: false))
        let initial = monitor.snapshot()
        let observation = try monitor.beginObservation(applicableImportIDs: initial.inFlight)
        defer { observation.close() }
        let start = ContinuousClock.now
        let final = await MCPReadRefreshPolicy.wait(monitor: monitor, initial: initial,
                                                    duration: .milliseconds(20),
                                                    observation: observation)
        #expect(start.duration(to: .now) < .milliseconds(500))
        #expect(final.generation == initial.generation)
    }

    @Test func applicableCompletionSurvivesLaterUnrelatedSameStoreEvents() async throws {
        for succeeds in [true, false] {
            let date = Date()
            let relevant = UUID()
            let unrelated = UUID()
            let monitor = MCPImportEvidenceMonitor(syncActive: true, storeIdentifier: "store")
            monitor.receive(.init(id: relevant, storeIdentifier: "store", kind: .import,
                                  startDate: date, endDate: nil, succeeded: false))
            let observation = try monitor.beginObservation(applicableImportIDs: [relevant])
            defer { observation.close() }
            let initial = monitor.snapshot(observation: observation)
            let final = await MCPReadRefreshPolicy.wait(monitor: monitor, initial: initial,
                                                        duration: .milliseconds(20),
                                                        observation: observation, sleep: { _ in
                monitor.receive(.init(id: relevant, storeIdentifier: "store", kind: .import,
                                      startDate: date, endDate: date, succeeded: succeeds))
                monitor.receive(.init(id: unrelated, storeIdentifier: "store", kind: .import,
                                      startDate: date, endDate: date, succeeded: succeeds))
            })
            let proof = MCPImportCaptureProof(storeIdentifier: "store", visibleImportIDs: [relevant])
            #expect(MCPReadRefreshPolicy.outcome(initial: initial, final: final, proof: proof,
                                                applicableInFlightIDs: [relevant])
                    == (succeeds ? .importObserved : .failed))
        }
    }

    @Test func windowCaptureKeepsVisibleSuccessAboveRelevantFailure() throws {
        let monitor = MCPImportEvidenceMonitor(syncActive: true, storeIdentifier: "store")
        let date = Date()
        let successID = UUID()
        let failureID = UUID()
        let window = try monitor.beginObservation(applicableImportIDs: [successID, failureID])
        defer { window.close() }
        for id in [successID, failureID] {
            monitor.receive(.init(id: id, storeIdentifier: "store", kind: .import,
                                  startDate: date, endDate: nil, succeeded: false))
        }
        let initial = monitor.snapshot(observation: window)
        monitor.receive(.init(id: successID, storeIdentifier: "store", kind: .import,
                              startDate: date, endDate: date, succeeded: true))
        monitor.receive(.init(id: failureID, storeIdentifier: "store", kind: .import,
                              startDate: date, endDate: date, succeeded: false))
        monitor.receive(.init(id: UUID(), storeIdentifier: "store", kind: .import,
                              startDate: date, endDate: date, succeeded: true))
        let capture = monitor.snapshot(observation: window)
        let proof = MCPImportCaptureProof(storeIdentifier: "store", visibleImportIDs: [successID])
        #expect(MCPReadRefreshPolicy.outcome(initial: initial, final: capture, proof: proof,
                                            applicableInFlightIDs: [successID, failureID]) == .importObserved)
        #expect(monitor.freshness(capture, proof: proof, asOf: Date(), now: .now).assessment == .recentImport)
        #expect(MCPReadRefreshPolicy.outcome(initial: initial, final: capture, proof: nil,
                                            applicableInFlightIDs: [successID, failureID]) == .failed)
        #expect(monitor.freshness(capture, proof: nil, asOf: Date(), now: .now).assessment == .unknown)
    }

}
#endif
