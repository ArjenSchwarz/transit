import Foundation

@main
struct PolicyProbe {
    static func main() throws {
        typealias Policy = AppPersistencePolicy
        func mode(_ development: Bool, _ bundle: String?, _ environment: [String: String] = [:],
                  runtime: Bool = false) throws -> Policy.Mode {
            try Policy.resolve(bundleID: bundle, developmentBuild: development,
                               environment: environment, testRuntimeDetected: runtime)
        }
        func expect(_ actual: Policy.Mode, _ expected: Policy.Mode) {
            precondition(actual == expected)
        }
        func rejects(_ operation: () throws -> Policy.Mode) {
            do { _ = try operation(); fatalError("Unsafe launch accepted") } catch {}
        }
        try expect(mode(false, Policy.productionBundleID), .production)
        try expect(mode(true, Policy.developmentBundleID), .development)
        rejects { try mode(true, Policy.productionBundleID) }
        rejects { try mode(false, Policy.developmentBundleID) }
        rejects { try mode(false, nil) }
        rejects { try mode(false, "me.nore.ig.Transit") }
        rejects { try mode(true, "me.nore.ig.Transit.development") }
        rejects { try mode(true, Policy.developmentBundleID, ["TRANSIT_PERSISTENCE_MODE": "production"]) }
        rejects { try mode(false, Policy.productionBundleID, ["TRANSIT_PERSISTENCE_MODE": "invalid"]) }
        rejects { try mode(false, Policy.productionBundleID, ["TRANSIT_PERSISTENCE_MODE": "unit-test"]) }
        for development in [false, true] {
            try expect(mode(development, Policy.developmentBundleID,
                                  ["TRANSIT_PERSISTENCE_MODE": "unit-test"]), .unitTest)
            try expect(mode(development, Policy.developmentBundleID,
                                  ["TRANSIT_PERSISTENCE_MODE": "ui-test"]), .uiTest)
            try expect(mode(development, Policy.developmentBundleID, runtime: true), .unitTest)
            try expect(mode(development, Policy.developmentBundleID,
                                  ["XCTestConfigurationFilePath": "/synthetic/test-config"]), .unitTest)
        }
        precondition(Policy.Mode.development.permitsCloudSync)
        precondition(!Policy.Mode.unitTest.permitsCloudSync && !Policy.Mode.uiTest.permitsCloudSync)
        precondition(Policy.Mode.development.cloudKitContainerID != Policy.Mode.production.cloudKitContainerID)
        precondition(Policy.Mode.production.defaultMCPPort == 3141)
        precondition(Policy.Mode.development.defaultMCPPort == 3142)
        precondition(!Policy.Mode.unitTest.permitsBackgroundServices)
        precondition(Policy.Mode.uiTest.usesMemoryStore)
        precondition(Policy.Mode.production.cloudKitContainerID == "iCloud.me.nore.ig.apps.Transit")
        precondition(Policy.Mode.development.cloudKitContainerID == "iCloud.me.nore.ig.apps.Transit.development")
        verifyStoreLocations()
        print("Persistence policy and fresh store/recovery location checks passed")
    }

    private static func verifyStoreLocations() {
        typealias Policy = AppPersistencePolicy
        let root = URL(fileURLWithPath: "/synthetic/application-support", isDirectory: true)
        let release = PersistenceStoreLocation.storeURL(for: .production, applicationSupportDirectory: root)!
        let development = PersistenceStoreLocation.storeURL(for: .development, applicationSupportDirectory: root)!
        precondition(release == root.appendingPathComponent("me.nore.ig.apps.Transit/release.store"))
        let developmentURL = root.appendingPathComponent("me.nore.ig.apps.Transit.development/development.store")
        precondition(development == developmentURL)
        precondition(release != development)
        for mode in [Policy.Mode.production, .development] {
            let selected = PersistenceStoreLocation.storeURL(for: mode, applicationSupportDirectory: root)!
            precondition(selected != root.appendingPathComponent("default.store"))
            precondition(selected != root.appendingPathComponent("TransitDevelopment/development.store"))
            let recovery = PersistenceStoreLocation.recoveryDirectory(for: mode, applicationSupportDirectory: root)
            precondition(recovery.deletingLastPathComponent() == selected.deletingLastPathComponent())
            precondition(recovery != root.appendingPathComponent("Backups"))
        }
        for mode in [Policy.Mode.unitTest, .uiTest] {
            precondition(PersistenceStoreLocation.storeURL(for: mode, applicationSupportDirectory: root) == nil)
        }
    }

}
