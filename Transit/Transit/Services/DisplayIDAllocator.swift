import CloudKit
import Foundation
import SwiftData

/// Allocates sequential display IDs (T-1, T-2, ...) using a CloudKit counter
/// record with optimistic locking. Falls back to provisional IDs when offline.
@Observable
final class DisplayIDAllocator: @unchecked Sendable {

    private let container: CKContainer
    private let database: CKDatabase

    private static let counterRecordType = "DisplayIDCounter"
    private static let counterRecordID = "global-counter"
    private static let nextDisplayIdKey = "nextDisplayId"
    private static let zoneName = "com.apple.coredata.cloudkit.zone"
    private static let maxRetries = 5

    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    private var recordID: CKRecord.ID {
        CKRecord.ID(recordName: Self.counterRecordID, zoneID: zoneID)
    }

    init(container: CKContainer) {
        self.container = container
        self.database = container.privateCloudDatabase
    }

    // MARK: - Public API

    /// Returns a provisional display ID for immediate use before CloudKit responds.
    func provisionalID() -> DisplayID {
        .provisional
    }

    /// Allocates the next sequential display ID from CloudKit. Retries on
    /// conflict up to `maxRetries` times.
    ///
    /// - Throws: `CKError` if allocation fails after all retries.
    /// - Returns: The allocated integer ID.
    func allocateNextID() async throws -> Int {
        for attempt in 0..<Self.maxRetries {
            do {
                return try await attemptAllocation()
            } catch let error as CKError where error.code == .serverRecordChanged {
                if attempt == Self.maxRetries - 1 {
                    throw error
                }
                // Retry — the next attempt will fetch the latest server record.
            }
        }
        // Unreachable, but satisfies the compiler.
        throw CKError(.internalError)
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
            } catch {
                // Stop promoting on first failure — remaining tasks keep provisional IDs.
                break
            }
        }
    }

    // MARK: - Private

    private func attemptAllocation() async throws -> Int {
        let existingRecord: CKRecord?

        do {
            existingRecord = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            existingRecord = nil
        }

        if let record = existingRecord {
            let currentNext = record[Self.nextDisplayIdKey] as? Int ?? 1
            record[Self.nextDisplayIdKey] = currentNext + 1
            try await saveWithOptimisticLocking(record)
            return currentNext
        } else {
            // First allocation: create the counter, return 1.
            let record = CKRecord(recordType: Self.counterRecordType, recordID: recordID)
            record[Self.nextDisplayIdKey] = 2
            try await database.save(record)
            return 1
        }
    }

    private func saveWithOptimisticLocking(_ record: CKRecord) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [record])
            operation.savePolicy = .ifServerRecordUnchanged
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
}
