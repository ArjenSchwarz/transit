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
        precondition(!Policy.Mode.development.permitsCloudSync)
        precondition(!Policy.Mode.unitTest.permitsBackgroundServices)
        precondition(Policy.Mode.uiTest.usesMemoryStore)
        print("Persistence policy checks passed")
    }
}
