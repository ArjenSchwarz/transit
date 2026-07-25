import CloudKit
import Foundation

/// The production `DisplayIDAllocator.CounterStore`: a single CloudKit record in the
/// private database holding the next display ID, updated with compare-and-swap via
/// `CKModifyRecordsOperation` and `.ifServerRecordUnchanged`.
///
/// Reached only when the live `ModelContainer` is CloudKit-backed — `DisplayIDAllocator`
/// refuses to call into this type when sync was off at launch (T-1797).
final class CloudKitCounterStore: DisplayIDAllocator.CounterStore {
    private static let counterRecordType = "DisplayIDCounter"
    private static let counterField = "nextDisplayId"
    private static let zoneID = CKRecordZone.ID(
        zoneName: "com.apple.coredata.cloudkit.zone",
        ownerName: CKCurrentUserDefaultName
    )

    private let counterRecordID: CKRecord.ID
    private let database: CKDatabase

    init(database: CKDatabase, recordName: String = "global-counter") {
        self.database = database
        self.counterRecordID = CKRecord.ID(recordName: recordName, zoneID: Self.zoneID)
    }

    func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
        do {
            let record = try await database.record(for: counterRecordID)
            let nextID = Self.extractNextDisplayID(from: record)
            return DisplayIDAllocator.CounterSnapshot(
                nextDisplayID: nextID,
                changeTag: record.recordChangeTag
            )
        } catch let error as CKError where error.code == .unknownItem {
            return DisplayIDAllocator.CounterSnapshot(nextDisplayID: 1, changeTag: nil)
        }
    }

    func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws {
        let record: CKRecord
        if let expectedChangeTag {
            let fetchedRecord = try await database.record(for: counterRecordID)
            guard fetchedRecord.recordChangeTag == expectedChangeTag else {
                throw DisplayIDAllocator.Error.conflict
            }
            record = fetchedRecord
        } else {
            record = CKRecord(recordType: Self.counterRecordType, recordID: counterRecordID)
        }
        record[Self.counterField] = NSNumber(value: nextDisplayID)

        do {
            try await modify(recordsToSave: [record])
        } catch let error as CKError where error.code == .serverRecordChanged {
            throw DisplayIDAllocator.Error.conflict
        }
    }

    private func modify(recordsToSave: [CKRecord]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            let operation = CKModifyRecordsOperation(
                recordsToSave: recordsToSave,
                recordIDsToDelete: nil
            )
            operation.savePolicy = .ifServerRecordUnchanged
            operation.isAtomic = true
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    private static func extractNextDisplayID(from record: CKRecord) -> Int {
        if let number = record[counterField] as? NSNumber {
            return max(1, number.intValue)
        }
        if let value = record[counterField] as? Int {
            return max(1, value)
        }
        return 1
    }
}
