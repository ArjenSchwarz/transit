import Foundation
import Testing
@testable import Transit

@MainActor
struct DevelopmentIsolationSmokeTests {
    @Test("Actual isolated host bootstrap uses no persistent or CloudKit store",
          .enabled(if: ProcessInfo.processInfo.environment["TRANSIT_ISOLATION_SMOKE"] == "1"))
    func actualHostBootstrap() throws {
        #expect(AppIsolationSmoke.enabled)
        let snapshot = try #require(AppIsolationSmoke.snapshot)
        #expect(Bundle.main.bundleIdentifier == AppPersistencePolicy.developmentBundleID)
        #expect(snapshot.mode == .unitTest)
        #expect(snapshot.memoryOnly && !snapshot.cloudSyncActive && snapshot.disabledCounters)
        #expect(snapshot.sidecar.lastPathComponent.hasPrefix("mcp-tests-"))
        #expect(!snapshot.storeURL.path.contains("me.nore.ig.Transit/"))
        print("Isolated host mode=unit-test memoryOnly=true cloudSync=false disabledCounters=true")
        print("Isolated host configuration URL=\(snapshot.storeURL.path) sidecar=\(snapshot.sidecar.path)")
    }
}
