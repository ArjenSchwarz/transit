#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

/// One stage per test-host process. The external runner proves each preceding
/// host exited before starting another; this test never launches child tests.
@MainActor @Suite(.serialized)
struct TaskLinkClosedStoreMigrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["T1734_CLOSED_STAGE"] != nil))
    func closedStoreStage() throws {
        let environment = ProcessInfo.processInfo.environment
        let stage = try #require(environment["T1734_CLOSED_STAGE"])
        _ = try #require(["seed", "legacy", "upgrade", "reopen"].contains(stage))
        let token = try #require(environment["T1734_CLOSED_TOKEN"].flatMap(UUID.init(uuidString:)))
        let root = try guardedRoot(token: token, stage: stage)
        let manager = FileManager.default
        let manifest = root.appendingPathComponent("original.json")
        let observation = root.appendingPathComponent("\(stage).json")
        _ = try #require(!manager.fileExists(atPath: observation.path))
        let isSeed = stage == "seed"
        _ = try #require(isSeed ? !manager.fileExists(atPath: root.path)
                               : manager.fileExists(atPath: manifest.path))
        let isCurrent = stage == "upgrade" || stage == "reopen"
        let schema: Schema? = isCurrent ? try TestModelContainer().container.schema : nil
        let fixture = try TaskLinkPreFeatureDiskFixture(directory: root, schema: schema, seed: isSeed)
        let original = isSeed ? try fixture.savedFields(in: fixture.owner.context) : nil
        if isSeed { try fixture.owner.context.save() }
        let bytes = try fixture.savedFields(in: fixture.owner.context)
        if isSeed {
            let expected = try #require(original)
            _ = try #require(bytes == expected)
            try bytes.write(to: manifest, options: .withoutOverwriting)
        } else {
            let expected = try Data(contentsOf: manifest)
            _ = try #require(bytes == expected)
        }
        let names = Set(fixture.owner.container.schema.entities.map(\.name))
        let missing = Set(["TaskLinkOccurrence", "TaskLinkRemovalEvidence"]).subtracting(names).sorted()
        let evidence: [String: Any] = [
            "stage": stage, "token": token.uuidString, "pid": ProcessInfo.processInfo.processIdentifier,
            "root": root.path, "store": fixture.storeURL.path, "rawFieldsPreserved": true,
            "schemaEntities": names.sorted(), "missingLinkEntities": missing,
            "cloudKit": "none", "closedStoreProvedByThisProcess": false
        ]
        try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys])
            .write(to: observation, options: .withoutOverwriting)
        // Upgrade uses the actual default test schema. Absence is behavioral
        // RED; neither a fabricated candidate schema nor missing Swift types.
        if isCurrent { _ = try #require(missing.isEmpty) }
        _ = try #require(!fixture.owner.context.hasChanges)
    }
    private func guardedRoot(token: UUID, stage: String) throws -> URL {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let expectedSuffix = "/Library/Containers/me.nore.ig.Transit.development/Data"
        _ = try #require(home.path.hasSuffix(expectedSuffix))
        let root = home.appendingPathComponent("tmp/T1734Closed-\(token.uuidString)", isDirectory: true)
        let manager = FileManager.default
        let manifest = root.appendingPathComponent("original.json")
        let observation = root.appendingPathComponent("\(stage).json")
        let canonicalHome = home.resolvingSymlinksInPath()
        _ = try #require(canonicalHome.path == home.path)
        let temp = home.appendingPathComponent("tmp", isDirectory: true)
        _ = try #require(manager.fileExists(atPath: temp.path))
        _ = try #require(temp.resolvingSymlinksInPath().path == canonicalHome.appendingPathComponent("tmp").path)
        let expectedRoot = canonicalHome.appendingPathComponent("tmp/T1734Closed-\(token.uuidString)")
        _ = try #require(root.resolvingSymlinksInPath().path == expectedRoot.path)
        let leaves = [root, manifest, observation, root.appendingPathComponent("pre-feature.store"),
                      root.appendingPathComponent("pre-feature.store-wal"),
                      root.appendingPathComponent("pre-feature.store-shm")]
        for leaf in leaves {
            _ = try #require((try? manager.destinationOfSymbolicLink(atPath: leaf.path)) == nil)
        }
        return root
    }
}

/// Local precheck only; never creates a CloudKit container or sends a request.
/// The development record/deletion gate needs the real task2 models and a
/// separately cleared signed CloudKit development host/operator fixture.
@MainActor @Suite(.serialized)
struct TaskLinkDevelopmentSchemaPrecheckTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["T1734_DEV_SCHEMA_PRECHECK"] == "1"))
    func developmentVerificationIsNotSatisfiedByLocalRegistration() throws {
        let fixture = try TestModelContainer()
        _ = try #require(fixture.container.schema.entitiesByName["TaskLinkOccurrence"])
        _ = try #require(fixture.container.schema.entitiesByName["TaskLinkRemovalEvidence"])
        Issue.record("Local schema precheck only: cleared development schema and platform deletion evidence required")
    }
}
#endif
