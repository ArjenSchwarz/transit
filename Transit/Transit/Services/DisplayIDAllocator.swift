import CloudKit
import Foundation
import SwiftData

/// Allocates sequential display IDs (T-1, T-2, ...) using a CloudKit counter
/// record with optimistic locking. Falls back to provisional IDs when offline.
@Observable
final class DisplayIDAllocator: @unchecked Sendable {

    /// Snapshot of the counter state used for optimistic locking.
    struct CounterSnapshot {
        let nextDisplayID: Int
        let changeTag: String?
    }

    enum Error: Swift.Error, Equatable {
        case conflict
        case retriesExhausted
    }

    /// Abstracts the counter persistence so tests can inject an in-memory store.
    protocol CounterStore {
        func loadCounter() async throws -> CounterSnapshot
        func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws
    }

    private let store: CounterStore
    private let retryLimit: Int

    init(store: CounterStore, retryLimit: Int = 5) {
        self.store = store
        self.retryLimit = max(1, retryLimit)
    }

    convenience init(
        container: CKContainer = .default(),
        counterRecordName: String = "global-counter",
        retryLimit: Int = 5
    ) {
        self.init(
            store: CloudKitCounterStore(
                database: container.privateCloudDatabase,
                recordName: counterRecordName
            ),
            retryLimit: retryLimit
        )
    }

    // MARK: - Public API

    /// Returns a provisional display ID for immediate use before CloudKit responds.
    func provisionalID() -> DisplayID {
        .provisional
    }

    /// Allocates the next sequential display ID. Retries on conflict up to
    /// `retryLimit` times.
    func allocateNextID() async throws -> Int {
        var attempt = 0
        while attempt < retryLimit {
            attempt += 1

            let snapshot = try await store.loadCounter()
            let allocatedID = snapshot.nextDisplayID

            do {
                try await store.saveCounter(
                    nextDisplayID: allocatedID + 1,
                    expectedChangeTag: snapshot.changeTag
                )
                return allocatedID
            } catch let error as Error where error == .conflict {
                continue
            }
        }

        throw Error.retriesExhausted
    }

    /// Finds tasks with provisional display IDs (permanentDisplayId == nil),
    /// sorts them by creation date, and allocates permanent IDs one at a time.
    func promoteProvisionalTasks(in context: ModelContext) async {
        let descriptor = FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.permanentDisplayId == nil },
            sortBy: [SortDescriptor(\.creationDate, order: .forward)]
        )

        guard let tasks = try? context.fetch(descriptor), !tasks.isEmpty else {
            return
        }

        for task in tasks {
            do {
                let newID = try await allocateNextID()
                task.permanentDisplayId = newID
                try context.save()
            } catch {
                // Stop promoting on first failure — remaining tasks keep provisional IDs.
                break
            }
        }
    }
}

// MARK: - CloudKit Implementation

private final class CloudKitCounterStore: DisplayIDAllocator.CounterStore {
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
