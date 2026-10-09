import Foundation

/// Decides persistence before any store, sync service or background task is created.
nonisolated enum AppPersistencePolicy {
    static let productionBundleID = "me.nore.ig.Transit"
    static let developmentBundleID = "me.nore.ig.Transit.development"

    enum Mode: Equatable, Sendable {
        case production
        case development
        case unitTest
        case uiTest

        var usesMemoryStore: Bool { self == .unitTest || self == .uiTest }
        var permitsCloudSync: Bool { self == .production || self == .development }
        var permitsBackgroundServices: Bool { !usesMemoryStore }
        var permitsAutomaticMCPStartup: Bool { !usesMemoryStore }

        var defaultMCPPort: Int { self == .production ? 3141 : 3142 }
        var displayName: String {
            switch self {
            case .production: "Release"
            case .development: "Debug"
            case .unitTest: "Debug (unit test)"
            case .uiTest: "Debug (UI test)"
            }
        }
        var cloudKitContainerID: String {
            self == .production ? "iCloud.me.nore.ig.Transit" : "iCloud.me.nore.ig.Transit.development"
        }
    }

    enum Failure: Error, Equatable {
        case invalidLaunchMode
        case developmentUsesProductionIdentity
        case testUsesProductionIdentity
        case unexpectedProductionIdentity
    }

    static func resolve(
        bundleID: String?,
        developmentBuild: Bool,
        environment: [String: String],
        testRuntimeDetected: Bool
    ) throws -> Mode {
        func isolatedTest(_ mode: Mode) throws -> Mode {
            guard bundleID == developmentBundleID else { throw Failure.testUsesProductionIdentity }
            return mode
        }
        // Explicit scheme/runner configuration is primary; runtime detection only
        // provides an additional isolated fallback, never access to live storage.
        if let requested = environment["TRANSIT_PERSISTENCE_MODE"] {
            switch requested {
            case "unit-test": return try isolatedTest(.unitTest)
            case "ui-test": return try isolatedTest(.uiTest)
            default: throw Failure.invalidLaunchMode
            }
        }
        if environment["TRANSIT_UI_TEST_SCENARIO"] != nil { return try isolatedTest(.uiTest) }
        let testKeys = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCInjectBundleInto"]
        if testRuntimeDetected || testKeys.contains(where: { environment[$0] != nil }) {
            return try isolatedTest(.unitTest)
        }
        if developmentBuild {
            guard bundleID == developmentBundleID else {
                throw Failure.developmentUsesProductionIdentity
            }
            return .development
        }
        guard bundleID == productionBundleID else { throw Failure.unexpectedProductionIdentity }
        return .production
    }

    static var serverName: String { isDevelopmentBuild ? "transit-debug" : "transit" }

    /// The build flag and entitlement selector are paired in the Xcode configuration.
    static var developmentCloudSyncEnabled: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "TransitDevelopmentCloudSync")
        return value as? String == "YES" || value as? Bool == true
    }

    static var isDevelopmentBuild: Bool {
        #if DEBUG || TRANSIT_DEVELOPMENT
        true
        #else
        false
        #endif
    }

    static var current: Mode {
        do {
            return try resolve(
                bundleID: Bundle.main.bundleIdentifier, developmentBuild: isDevelopmentBuild,
                environment: ProcessInfo.processInfo.environment,
                testRuntimeDetected: NSClassFromString("XCTestCase") != nil
            )
        } catch {
            fatalError("Refusing unsafe Transit persistence configuration: \(error)")
        }
    }
}
