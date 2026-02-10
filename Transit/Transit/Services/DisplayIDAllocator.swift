import CloudKit
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class DisplayIDAllocator {
    struct CounterSnapshot {
        let nextDisplayID: Int
        let changeTag: String?
    }

    enum Error: Swift.Error, Equatable {
        case conflict
        case retriesExhausted
    }

    protocol CounterStore {
        func loadCounter() async throws -> CounterSnapshot
        func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws
    }

    private let store: CounterStore
    private let retryLimit: Int

    init(store: CounterStore, retryLimit: Int = 8) {
        self.store = store
        self.retryLimit = max(1, retryLimit)
    }

    convenience init(container: CKContainer = .default(), retryLimit: Int = 8) {
        self.init(store: CloudKitCounterStore(database: container.privateCloudDatabase), retryLimit: retryLimit)
    }

    func allocateNextID() async throws -> Int {
        var attempt = 0
        while attempt < retryLimit {
            attempt += 1

            let snapshot = try await store.loadCounter()
            let allocatedID = snapshot.nextDisplayID

            do {
                try await store.saveCounter(nextDisplayID: allocatedID + 1, expectedChangeTag: snapshot.changeTag)
                return allocatedID
            } catch let error as Error where error == .conflict {
                continue
            }
        }

        throw Error.retriesExhausted
    }

    func provisionalID() -> DisplayID {
        .provisional
    }

    func promoteProvisionalTasks(in context: ModelContext) async {
        let predicate = #Predicate<TransitTask> { task in
            task.permanentDisplayId == nil
        }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\TransitTask.creationDate)]
        )

        guard let tasks = try? context.fetch(descriptor) else {
            return
        }

        for task in tasks {
            do {
                let id = try await allocateNextID()
                task.permanentDisplayId = id
                try context.save()
            } catch {
                break
            }
        }
    }
}

private final class CloudKitCounterStore: DisplayIDAllocator.CounterStore {
    private static let counterRecordType = "DisplayIDCounter"
    private static let counterField = "nextDisplayId"
    private static let zoneID = CKRecordZone.ID(
        zoneName: "com.apple.coredata.cloudkit.zone",
        ownerName: CKCurrentUserDefaultName
    )
    private static let counterRecordID = CKRecord.ID(recordName: "global-counter", zoneID: zoneID)

    private let database: CKDatabase

    init(database: CKDatabase) {
        self.database = database
    }

    func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
        do {
            let record = try await database.record(for: Self.counterRecordID)
            let nextID = Self.extractNextDisplayID(from: record)
            return DisplayIDAllocator.CounterSnapshot(nextDisplayID: nextID, changeTag: record.recordChangeTag)
        } catch let error as CKError where error.code == .unknownItem {
            return DisplayIDAllocator.CounterSnapshot(nextDisplayID: 1, changeTag: nil)
        } catch {
            throw error
        }
    }

    func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws {
        let record: CKRecord
        if let expectedChangeTag {
            do {
                let fetchedRecord = try await database.record(for: Self.counterRecordID)
                guard fetchedRecord.recordChangeTag == expectedChangeTag else {
                    throw DisplayIDAllocator.Error.conflict
                }
                record = fetchedRecord
            } catch let error as CKError where error.code == .unknownItem {
                throw DisplayIDAllocator.Error.conflict
            }
        } else {
            record = CKRecord(recordType: Self.counterRecordType, recordID: Self.counterRecordID)
        }
        record[Self.counterField] = NSNumber(value: nextDisplayID)

        do {
            try await modify(recordsToSave: [record])
        } catch let error as CKError where error.code == .serverRecordChanged {
            throw DisplayIDAllocator.Error.conflict
        } catch {
            throw error
        }
    }

    private func modify(recordsToSave: [CKRecord]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: nil)
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
