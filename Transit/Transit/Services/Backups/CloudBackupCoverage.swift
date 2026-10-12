@preconcurrency import CloudKit
import Foundation

/// An online preflight prevents a local-only backup from authorizing deletion of unknown cloud data.
/// Wipe uses SwiftData's ordinary deletion exports; it never resets CloudKit zones or mirror metadata.
@MainActor
struct CloudBackupCoverage {
    let database: CKDatabase

    func verify(_ archive: DatabaseArchive) async throws {
        let zones = try Self.transitZones(await database.allRecordZones())
        for zone in zones {
            var token: CKServerChangeToken?
            var savedRecords: [CKRecord.ID: CKRecord] = [:]
            var more = true
            while more {
                let page = try await database.recordZoneChanges(inZoneWith: zone.zoneID, since: token)
                for result in page.modificationResultsByID.values {
                    let record = try result.get().record
                    savedRecords[record.recordID] = record
                }
                let removed = Set(page.deletions.map(\.recordID))
                for id in removed { savedRecords.removeValue(forKey: id) }
                token = page.changeToken
                more = page.moreComing
                guard savedRecords.count <= 100_000 else {
                    throw DatabaseBackupError.invalidArchive("iCloud exceeds the safe verification limit.")
                }
            }
            try Self.verifyRecords(Array(savedRecords.values), archive: archive)
        }
    }

    /// CloudKit always includes its default zone; Transit writes only to the Core Data custom zone.
    static func transitZones(_ zones: [CKRecordZone]) throws -> [CKRecordZone] {
        let custom = zones.filter { $0.zoneID != CKRecordZone.default().zoneID }
        guard custom.allSatisfy({ $0.zoneID.zoneName == "com.apple.coredata.cloudkit.zone" }) else {
            throw DatabaseBackupError.invalidArchive("An unexpected iCloud zone prevents a safe wipe.")
        }
        return custom
    }

    static func verifyRecords(_ records: [CKRecord], archive: DatabaseArchive) throws {
        try archive.validate()
        let expected = try archive.cloudRows()
        let relationships = archive.cloudRelationshipRows()
        var byRecordID: [CKRecord.ID: CKRecord] = [:]
        for record in records {
            guard byRecordID.updateValue(record, forKey: record.recordID) == nil else {
                throw DatabaseBackupError.invalidArchive("Duplicate physical cloud records prevent a safe wipe.")
            }
        }
        var seen: Set<String> = []
        for record in records {
            // CloudKit mirror records and ID allocation are infrastructure, not user content.
            if record.recordType == "CDMR" || record.recordType == "DisplayIDCounter"
                || record.recordType == "CD_SyncHeartbeat" {
                continue
            }
            guard let rows = expected[record.recordType],
                let identifier = record["CD_id"] as? String,
                let uuid = UUID(uuidString: identifier), let fields = rows[uuid.uuidString]
            else {
                throw DatabaseBackupError.invalidArchive(
                    "iCloud contains data absent from this backup. Allow sync to finish, then retry.")
            }
            guard seen.insert(record.recordType + uuid.uuidString).inserted else {
                throw DatabaseBackupError.invalidArchive("Duplicate physical iCloud identities prevent a safe wipe.")
            }
            for (field, value) in fields where field != "id" && !field.hasSuffix("Row") {
                let cloudValue = record["CD_" + field]
                guard Self.matches(value, cloudValue) else {
                    throw DatabaseBackupError.invalidArchive(
                        "iCloud has a different version of a saved record. Allow sync to finish, then retry.")
                }
            }
            for (relationship, targetID) in relationships[record.recordType]?[uuid] ?? [] {
                let reference = record["CD_" + relationship] as? CKRecord.Reference
                let actual = reference.flatMap { byRecordID[$0.recordID]?["CD_id"] as? String }.flatMap(
                    UUID.init(uuidString:))
                guard actual == targetID else {
                    throw DatabaseBackupError.invalidArchive(
                        "An iCloud relationship is not covered by this backup.")
                }
            }
        }
    }

    private static func matches(_ local: Any, _ cloud: Any?) -> Bool {
        if local is NSNull { return cloud == nil }
        if let string = local as? String {
            guard let remote = cloud as? String else { return false }
            if let uuid = UUID(uuidString: string) { return UUID(uuidString: remote) == uuid }
            return remote == string
        }
        if let number = local as? NSNumber {
            if let date = cloud as? Date {
                return abs(date.timeIntervalSinceReferenceDate - number.doubleValue) < 0.001
            }
            return (cloud as? NSNumber) == number
        }
        return false
    }
}

extension DatabaseArchive {
    func cloudRows() throws -> [String: [String: [String: Any]]] {
        let encoder = JSONEncoder()
        func rows<T: Encodable>(_ values: [T], optionalFields: [String] = []) throws -> [String: [String: Any]] {
            let data = try encoder.encode(values)
            let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
            var result: [String: [String: Any]] = [:]
            for object in objects {
                guard let id = object["id"] as? String, let uuid = UUID(uuidString: id),
                    result[uuid.uuidString] == nil
                else {
                    throw DatabaseBackupError.invalidArchive(
                        "Resolve duplicate physical IDs before an iCloud wipe.")
                }
                var fields = object
                for field in optionalFields where fields[field] == nil { fields[field] = NSNull() }
                result[uuid.uuidString] = fields
            }
            return result
        }
        return try [
            "CD_Project": rows(projectRows, optionalFields: ["gitRepo"]),
            "CD_TransitTask": rows(
                transitTaskRows,
                optionalFields: ["permanentDisplayId", "taskDescription", "completionDate", "metadataJSON"]),
            "CD_Milestone": rows(
                milestoneRows, optionalFields: ["permanentDisplayId", "milestoneDescription", "completionDate"]),
            "CD_Comment": rows(commentRows),
            "CD_MCPWriteReceipt": rows(
                mCPWriteReceiptRows, optionalFields: ["completedAt", "expiresAt", "resultJSON", "resultIsError"]),
            "CD_TaskLinkOccurrence": rows(taskLinkOccurrenceRows),
            "CD_TaskLinkRemovalEvidence": rows(taskLinkRemovalEvidenceRows),
            "CD_TaskConsolidationEvent": rows(
                taskConsolidationEventRows,
                optionalFields: ["candidate1", "candidate2", "candidate3", "candidate4", "candidate5"])
        ]
    }

    func cloudRelationshipRows() -> [String: [UUID: [(String, UUID?)]]] {
        let tasks = transitTaskRows.map { row in
            (
                row.id,
                [
                    ("project", row.projectRow.map { projectRows[$0].id }),
                    ("milestone", row.milestoneRow.map { milestoneRows[$0].id })
                ]
            )
        }
        let milestones = milestoneRows.map { row in
            (row.id, [("project", row.projectRow.map { projectRows[$0].id })])
        }
        let comments = commentRows.map { row in
            (row.id, [("task", row.taskRow.map { transitTaskRows[$0].id })])
        }
        return [
            "CD_TransitTask": Dictionary(uniqueKeysWithValues: tasks),
            "CD_Milestone": Dictionary(uniqueKeysWithValues: milestones),
            "CD_Comment": Dictionary(uniqueKeysWithValues: comments)
        ]
    }
}
