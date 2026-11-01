import CloudKit
import CryptoKit
import Foundation
import SwiftData

/// Reads only Transit's custom zone. Default-zone data is outside Transit's storage contract.
@MainActor final class MigrationCloudInspection: MigrationCounterPreflight.Cloud {
    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone",
                                         ownerName: CKCurrentUserDefaultName)
    let tasks: any DisplayIDAllocator.CounterStore
    let milestones: any DisplayIDAllocator.CounterStore
    private static let contentTypes: Set<String> = [
        "CD_Project", "CD_TransitTask", "CD_Milestone", "CD_Comment", "CD_MCPWriteReceipt",
        "CD_TaskLinkOccurrence", "CD_TaskLinkRemovalEvidence", "CD_TaskConsolidationEvent"
    ]

    init() {
        let container = CKContainer(identifier: MigrationCounterPreflight.Destination.release.container)
        self.container = container
        self.database = container.privateCloudDatabase
        self.tasks = CloudKitCounterStore(database: container.privateCloudDatabase, recordName: "global-counter")
        self.milestones = CloudKitCounterStore(
            database: container.privateCloudDatabase, recordName: "milestone-counter")
    }

    func account() async throws -> String {
        guard try await container.accountStatus() == .available else {
            throw MigrationCounterPreflight.Failure.unavailable
        }
        let id = try await container.userRecordID()
        return SHA256.hash(data: Data(id.recordName.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func inspect() async throws -> MigrationCounterPreflight.Inventory {
        let identity = try await account()
        let zones = try await database.allRecordZones().filter { $0.zoneID != CKRecordZone.default().zoneID }
        let unexpected = zones.filter { $0.zoneID != zoneID }.map { $0.zoneID.zoneName }.sorted()
        var inventory = MigrationInventoryAccumulator()
        if zones.contains(where: { $0.zoneID == zoneID }) {
            var token: CKServerChangeToken?
            var more = true
            while more {
                try Task.checkCancellation()
                let page = try await database.recordZoneChanges(
                    inZoneWith: zoneID, since: token, desiredKeys: ["nextDisplayId"])
                for (id, result) in page.modificationResultsByID {
                    let record = try result.get().record
                    try inventory.record(id: id.recordName, type: record.recordType,
                                         counter: (record["nextDisplayId"] as? NSNumber)?.intValue)
                }
                for removed in page.deletions { inventory.delete(id: removed.recordID.recordName) }
                token = page.changeToken
                more = page.moreComing
                try inventory.finishPage()
            }
        }
        guard try await account() == identity else { throw MigrationCounterPreflight.Failure.invalidReceipt }
        let counts = inventory.counts
        let known = Self.contentTypes.union(["CDMR", "CD_SyncHeartbeat", "DisplayIDCounter"])
        return MigrationCounterPreflight.Inventory(account: identity, counts: counts,
            unexpectedZones: unexpected, unexpectedTypes: counts.keys.filter { !known.contains($0) }.sorted(),
            taskCounter: inventory.counters["global-counter"] ?? 1,
            milestoneCounter: inventory.counters["milestone-counter"] ?? 1)
    }

    /// Called only after explicit fresh-destination preparation, never by inspect/verifySaved.
    func ensureZone() async throws {
        let zones = try await database.allRecordZones()
        if !zones.contains(where: { $0.zoneID == zoneID }) {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
        }
    }
}

extension MigrationCloudInspection {
    static func makePreflight(configuration: ModelConfiguration, container: ModelContainer, durable: Bool,
                              syncActive: Bool) -> MigrationCounterPreflight {
        let expected = MigrationCounterPreflight.Destination.release
        let enabled = durable && syncActive
            && configuration.cloudKitContainerIdentifier == expected.container
            && Bundle.main.bundleIdentifier == AppPersistencePolicy.productionBundleID
            && Bundle.main.object(forInfoDictionaryKey: "TransitSigningTeam") as? String == expected.team
            && Bundle.main.object(forInfoDictionaryKey: "TransitCloudEnvironment") as? String == expected.environment
        let defaults = UserDefaults.standard
        let key = "migration.counter-readiness.v1"
        return MigrationCounterPreflight(destination: expected, enabled: enabled, cloud: MigrationCloudInspection(),
            canPrepareFresh: { try MigrationLocalInspection.isEmpty(container) }, readReceipt: {
                guard let value = defaults.object(forKey: key) else { return nil }
                guard let data = value as? Data else { throw MigrationCounterPreflight.Failure.invalidReceipt }
                return data
            }, writeReceipt: { data in
                defaults.set(data, forKey: key)
                guard defaults.data(forKey: key) == data else { throw MigrationCounterPreflight.Failure.invalidReceipt }
            })
    }
}
