import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor
@Suite(.serialized)
struct AppEnvironmentTests {
    @Test func debugConfigurationCannotBindReleaseCloud() throws {
        let schema = Schema([Project.self])
        #expect(throws: IsolatedPersistenceConfiguration.Failure.invalidCloudContainer) {
            try IsolatedPersistenceConfiguration.make(mode: .development, schema: schema,
                cloudKitContainerID: AppPersistencePolicy.Mode.production.cloudKitContainerID)
        }
        #expect(throws: IsolatedPersistenceConfiguration.Failure.invalidCloudContainer) {
            try IsolatedPersistenceConfiguration.make(mode: .unitTest, schema: schema,
                cloudKitContainerID: AppPersistencePolicy.Mode.development.cloudKitContainerID)
        }
    }

    #if os(macOS)
    @Test func independentMCPDefaultsAndExplicitOverrides() throws {
        let releaseName = "transit-release-fixture-" + UUID().uuidString
        let debugName = "transit-debug-fixture-" + UUID().uuidString
        let release = try #require(UserDefaults(suiteName: releaseName))
        let debug = try #require(UserDefaults(suiteName: debugName))
        defer {
            release.removePersistentDomain(forName: releaseName)
            debug.removePersistentDomain(forName: debugName)
        }
        let releaseSettings = MCPSettings(mode: .production, defaults: release)
        let debugSettings = MCPSettings(mode: .development, defaults: debug)
        #expect(releaseSettings.port == 3141 && debugSettings.port == 3142)
        releaseSettings.port = 3201
        debugSettings.port = 3202
        #expect(MCPSettings(mode: .production, defaults: release).port == 3201)
        #expect(MCPSettings(mode: .development, defaults: debug).port == 3202)
        debugSettings.isEnabled = true
        #expect(!releaseSettings.isEnabled)
        debug.set(70000, forKey: "mcpServerPort")
        #expect(MCPSettings(mode: .development, defaults: debug).port == 3142)
    }
    #endif
}
