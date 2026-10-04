import CloudKit
import Foundation
import SwiftData

// Deliberately excluded from app/test targets. Task2 must supply the real model
// declarations and these explicit scalar initializers before compilation.
@MainActor @main
struct TaskLinkDevelopmentSmoke {
    struct Mapping: Decodable {
        let recordType: String
        let exemplarRecordName: String
        let fields: [String: String]
    }

    struct Contract: Decodable {
        let containerID: String
        let zoneName: String
        let ownerName: String
        let uuidRepresentation: String
        let reservedDevelopmentEnvironment: Bool
        let occurrence: Mapping
        let removal: Mapping
    }

    enum Failure: Error { case invalid(String) }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.invalid(message) }
    }

    static func main() async throws {
        let arguments = CommandLine.arguments
        try require(arguments.count == 3, "Expected reviewed contract and fresh private store directory")
        try require(ProcessInfo.processInfo.environment["T1734_DEV_SMOKE_CLEARED"] == "1",
                    "Reserved development host/slot clearance required")
        let contractBytes = try Data(contentsOf: URL(fileURLWithPath: arguments[1]))
        let contract = try JSONDecoder().decode(Contract.self, from: contractBytes)
        try require(contract.reservedDevelopmentEnvironment && contract.containerID.hasPrefix("iCloud."),
                    "Reserved development contract required")
        try require(["uuid-string", "uuid-data"].contains(contract.uuidRepresentation), "Unsupported UUID mapping")
        let directory = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        try require(!FileManager.default.fileExists(atPath: directory.path), "Fresh store required")
        let parent = directory.deletingLastPathComponent()
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let privateTemp = home.appendingPathComponent("tmp")
        try require(home.path.hasSuffix("/Library/Containers/me.nore.ig.Transit.development.cloudkit-smoke/Data"),
                    "Reserved smoke-host sandbox required")
        try require(parent == privateTemp && directory.lastPathComponent.hasPrefix("T1734Dev-"),
                    "Store must be in smoke-host private tmp")
        try require(parent.resolvingSymlinksInPath().path == parent.path, "Symlink parent forbidden")
        try require((try? FileManager.default.destinationOfSymbolicLink(atPath: directory.path)) == nil,
                    "Symlink store root forbidden")
        let database = CKContainer(identifier: contract.containerID).privateCloudDatabase
        let zone = CKRecordZone.ID(zoneName: contract.zoneName, ownerName: contract.ownerName)
        // Existing operator-pinned exemplars prevent creating a missing schema
        // as a side effect of the test's first SwiftData save.
        let occurrenceFields = ["id", "kindRawValue", "sourceTaskID", "targetTaskID", "createdAt"]
        let removalFields = occurrenceFields + ["edgeId", "occurrenceRevision", "removedAt"]
        try await validateExemplar(contract.occurrence, fields: occurrenceFields, database: database, zone: zone)
        try await validateExemplar(contract.removal, fields: removalFields, database: database, zone: zone)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        // Scalar-only models have no task relationships; register exactly these
        // two existing development record types to avoid initializing others.
        let schema = Schema([TaskLinkOccurrence.self, TaskLinkRemovalEvidence.self])
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("smoke.store"),
                                               cloudKitDatabase: .private(contract.containerID))
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try await verifyDeletion(context: context, database: database, zone: zone,
                                 contract: contract, directory: directory)
        // Retain all synthetic store/evidence files; no cleanup or direct CK delete.
        withExtendedLifetime(container) {}
    }

    static func validateExemplar(_ mapping: Mapping, fields: [String], database: CKDatabase,
                                 zone: CKRecordZone.ID) async throws {
        try require(Set(mapping.fields.keys) == Set(fields), "Complete field mapping required")
        try require(Set(mapping.fields.values).count == fields.count, "Distinct server fields required")
        let recordID = CKRecord.ID(recordName: mapping.exemplarRecordName, zoneID: zone)
        let record = try await database.configuredWith(configuration: networkPolicy()) { scoped in
            try await scoped.record(for: recordID)
        }
        try require(record.recordType == mapping.recordType, "Existing development record type mismatch")
        for field in fields {
            try require(record[mapping.fields[field]!] != nil, "Existing server field missing: \(field)")
        }
    }

    // The single storage/export/deletion sequence intentionally shows the whole smoke contract.
    // swiftlint:disable:next function_body_length
    static func verifyDeletion(context: ModelContext, database: CKDatabase, zone: CKRecordZone.ID,
                               contract: Contract, directory: URL) async throws {
        let edgeID = UUID(), removalID = UUID(), sourceID = UUID(), targetID = UUID()
        let created = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970))
        let occurrence = TaskLinkOccurrence(id: edgeID, kindRawValue: "association", sourceTaskID: sourceID,
                                            targetTaskID: targetID, createdAt: created)
        try require(occurrence.id == edgeID && occurrence.kindRawValue == "association"
                    && occurrence.sourceTaskID == sourceID && occurrence.targetTaskID == targetID
                    && occurrence.createdAt == created, "Local occurrence scalar fields mismatch")
        let expected: [String: Any] = ["id": edgeID, "kindRawValue": "association", "sourceTaskID": sourceID,
                                       "targetTaskID": targetID, "createdAt": created]
        context.insert(occurrence)
        try context.save()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(120))
        var token: CKServerChangeToken?
        var activeRecordID: CKRecord.ID?
        var visits = 0
        while activeRecordID == nil {
            try require(clock.now < deadline && visits < 64, "Occurrence export deadline/budget exceeded")
            let previous = token
            let page = try await database.configuredWith(configuration: networkPolicy()) { scoped in
                try await scoped.recordZoneChanges(inZoneWith: zone, since: previous, resultsLimit: 100)
            }
            token = page.changeToken
            visits += 1
            for change in page.modificationResultsByID.values {
                let record = try change.get().record
                if record.recordType == contract.occurrence.recordType,
                   matchesUUID(record[contract.occurrence.fields["id"]!], edgeID, contract.uuidRepresentation) {
                    try assertFields(record, mapping: contract.occurrence, expected: expected, contract: contract)
                    activeRecordID = record.recordID
                }
            }
            if !page.moreComing && activeRecordID == nil { try await Task.sleep(for: .seconds(1)) }
        }
        guard let originalRecordID = activeRecordID else { throw Failure.invalid("Occurrence record absent") }
        let removed = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970))
        let revision = "l1:" + String(repeating: "0", count: 64) // Storage smoke, not fingerprint verification.
        let evidence = TaskLinkRemovalEvidence(id: removalID, edgeId: edgeID, kindRawValue: "association",
                                              sourceTaskID: sourceID, targetTaskID: targetID, createdAt: created,
                                              occurrenceRevision: revision, removedAt: removed)
        context.delete(occurrence)
        context.insert(evidence)
        try context.save()
        var removalExpected = expected
        removalExpected["id"] = removalID
        removalExpected["edgeId"] = edgeID
        removalExpected["occurrenceRevision"] = revision
        removalExpected["removedAt"] = removed
        var deletionObserved = false, evidenceObserved = false
        while !deletionObserved || !evidenceObserved {
            try require(clock.now < deadline && visits < 64, "Platform deletion/export deadline/budget exceeded")
            let previous = token
            let page = try await database.configuredWith(configuration: networkPolicy()) { scoped in
                try await scoped.recordZoneChanges(inZoneWith: zone, since: previous, resultsLimit: 100)
            }
            token = page.changeToken
            visits += 1
            deletionObserved = deletionObserved || page.deletions.contains {
                $0.recordID == originalRecordID && $0.recordType == contract.occurrence.recordType
            }
            for change in page.modificationResultsByID.values {
                let record = try change.get().record
                if record.recordType == contract.removal.recordType,
                   matchesUUID(record[contract.removal.fields["id"]!], removalID, contract.uuidRepresentation) {
                    try assertFields(record, mapping: contract.removal, expected: removalExpected, contract: contract)
                    evidenceObserved = true
                }
            }
            if !page.moreComing && (!deletionObserved || !evidenceObserved) {
                try await Task.sleep(for: .seconds(1))
            }
        }
        var activeFetch = FetchDescriptor<TaskLinkOccurrence>(predicate: #Predicate { $0.id == edgeID })
        activeFetch.fetchLimit = 2
        try require(try context.fetch(activeFetch).isEmpty, "Run's local occurrence not deleted")
        var removalFetch = FetchDescriptor<TaskLinkRemovalEvidence>(predicate: #Predicate { $0.id == removalID })
        removalFetch.fetchLimit = 2
        let rows = try context.fetch(removalFetch)
        try require(rows.count == 1 && rows[0].id == removalID && rows[0].edgeId == edgeID,
                    "Local exact removal evidence missing")
        try require(rows[0].kindRawValue == "association" && rows[0].sourceTaskID == sourceID
                    && rows[0].targetTaskID == targetID && rows[0].createdAt == created
                    && rows[0].occurrenceRevision == revision && rows[0].removedAt == removed,
                    "Local removal scalar fields mismatch")
        let result: [String: Any] = ["edgeID": edgeID.uuidString, "removalID": removalID.uuidString,
                                    "recordName": originalRecordID.recordName, "zone": zone.zoneName,
                                    "platformDeletionObserved": deletionObserved,
                                    "evidenceExportObserved": evidenceObserved,
                                    "globalConvergenceClaim": false, "cloudKitAtomicityClaim": false]
        try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            .write(to: directory.appendingPathComponent("result.json"), options: .withoutOverwriting)
    }

    static func matchesUUID(_ value: CKRecordValue?, _ expected: UUID, _ representation: String) -> Bool {
        if representation == "uuid-string" { return (value as? String).flatMap(UUID.init(uuidString:)) == expected }
        var bytes = expected.uuid
        return value as? Data == withUnsafeBytes(of: &bytes) { Data($0) }
    }

    static func networkPolicy() -> CKOperation.Configuration {
        let configuration = CKOperation.Configuration()
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        return configuration
    }

    static func assertFields(_ record: CKRecord, mapping: Mapping, expected: [String: Any],
                             contract: Contract) throws {
        for (field, value) in expected {
            let saved = record[mapping.fields[field]!]
            if let uuid = value as? UUID {
                try require(matchesUUID(saved, uuid, contract.uuidRepresentation), "UUID field mismatch: \(field)")
            } else if let date = value as? Date {
                try require(saved as? Date == date, "Date field mismatch: \(field)")
            } else if let string = value as? String {
                try require(saved as? String == string, "String field mismatch: \(field)")
            } else { throw Failure.invalid("Unsupported field: \(field)") }
        }
    }
}
