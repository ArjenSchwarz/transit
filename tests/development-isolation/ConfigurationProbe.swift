import Foundation
import SwiftData

/// Uses real SwiftData configurations but no model macros, ModelContainer, app or cloud connection.
@main struct ConfigurationProbe {
    @MainActor static func main() throws {
        precondition(CommandLine.arguments.count == 2)
        let parent = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let root = parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("default.store")
        let marker = Data("untouched legacy fixture".utf8)
        try marker.write(to: legacy, options: .withoutOverwriting)
        let schema = Schema([])
        let release = try IsolatedPersistenceConfiguration.make(
            mode: .production, schema: schema, applicationSupportDirectory: root)
        let development = try IsolatedPersistenceConfiguration.make(
            mode: .development, schema: schema, applicationSupportDirectory: root)
        precondition(release.url != development.url && release.url != legacy && development.url != legacy)
        precondition(release.url == root.appendingPathComponent("me.nore.ig.apps.Transit/release.store"))
        let developmentURL = root.appendingPathComponent("me.nore.ig.apps.Transit.development/development.store")
        precondition(development.url == developmentURL)
        precondition(release.cloudKitContainerIdentifier == nil && development.cloudKitContainerIdentifier == nil)
        precondition(release.groupAppContainerIdentifier == nil && development.groupAppContainerIdentifier == nil)
        let recovery = try BackupRecoveryFiles.directory(applicationSupportDirectory: root, mode: .production)
        let expectedRecovery = release.url.deletingLastPathComponent()
            .appendingPathComponent("Backups", isDirectory: true)
        precondition(recovery == expectedRecovery)
        try verifyCloudSelectors(schema: schema, root: root, release: release, development: development)
        for mode in [AppPersistencePolicy.Mode.unitTest, .uiTest] {
            let unused = root.appendingPathComponent(UUID().uuidString)
            let memory = try IsolatedPersistenceConfiguration.make(
                mode: mode, schema: schema, applicationSupportDirectory: unused)
            precondition(memory.isStoredInMemoryOnly && memory.cloudKitContainerIdentifier == nil)
            precondition(!FileManager.default.fileExists(atPath: unused.path))
        }
        let retainedMarker = try Data(contentsOf: legacy)
        precondition(retainedMarker == marker)
        precondition(!FileManager.default.fileExists(atPath: release.url.path))
        precondition(!FileManager.default.fileExists(atPath: development.url.path))
        print("Actual SwiftData configuration checks passed: paths, selectors, memory modes, legacy sentinel unchanged")
    }

    @MainActor private static func verifyCloudSelectors(
        schema: Schema, root: URL, release: ModelConfiguration, development: ModelConfiguration
    ) throws {
        for (mode, expected) in [(AppPersistencePolicy.Mode.production, release), (.development, development)] {
            let cloud = try IsolatedPersistenceConfiguration.make(mode: mode, schema: schema,
                applicationSupportDirectory: root, cloudKitContainerID: mode.cloudKitContainerID)
            precondition(cloud.url == expected.url && cloud.cloudKitContainerIdentifier == mode.cloudKitContainerID)
            precondition(cloud.groupAppContainerIdentifier == nil)
        }
        for (mode, wrong) in [
            (AppPersistencePolicy.Mode.production, AppPersistencePolicy.Mode.development.cloudKitContainerID),
            (.development, AppPersistencePolicy.Mode.production.cloudKitContainerID),
            (.production, "iCloud.me.nore.ig.Transit"),
            (.development, "iCloud.me.nore.ig.Transit.development"),
            (.unitTest, AppPersistencePolicy.Mode.development.cloudKitContainerID)
        ] {
            let unused = root.appendingPathComponent(UUID().uuidString)
            do {
                _ = try IsolatedPersistenceConfiguration.make(mode: mode, schema: schema,
                    applicationSupportDirectory: unused, cloudKitContainerID: wrong)
                fatalError("Invalid cloud selector accepted")
            } catch IsolatedPersistenceConfiguration.Failure.invalidCloudContainer {}
            precondition(!FileManager.default.fileExists(atPath: unused.path))
        }
    }
}
