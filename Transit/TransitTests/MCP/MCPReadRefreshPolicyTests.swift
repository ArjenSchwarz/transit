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
                                             recent: false, remaining: .seconds(5)) == .wait(.seconds(2)))
        #expect(MCPReadRefreshPolicy.decision(policy: .refreshIfNeeded, snapshot: state,
                                             recent: false, remaining: .milliseconds(250)) == .wait(.milliseconds(250)))
        #expect(MCPReadRefreshPolicy.decision(policy: .refreshIfNeeded, snapshot: state,
                                             recent: false, remaining: .zero) == .skip(.timeout))
        let inactive = MCPImportEvidenceMonitor(syncActive: false, storeIdentifier: "store").snapshot()
        #expect(MCPReadRefreshPolicy.decision(policy: .refreshIfNeeded, snapshot: inactive,
                                             recent: true, remaining: .seconds(5)) == .skip(.notRequested))
    }
}
#endif
