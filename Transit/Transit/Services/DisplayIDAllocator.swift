//
//  DisplayIDAllocator.swift
//  Transit
//
//  Manages CloudKit counter for sequential display ID allocation.
//

import CloudKit
import Foundation
import SwiftData

@Observable
final class DisplayIDAllocator {
    private let container: CKContainer
    private let database: CKDatabase

    private static let counterRecordType = "DisplayIDCounter"
    private static let zoneID = CKRecordZone.ID(
        zoneName: "com.apple.coredata.cloudkit.zone",
        ownerName: CKCurrentUserDefaultName
    )
    private static let counterRecordID = CKRecord.ID(
        recordName: "global-counter",
        zoneID: zoneID
    )
    private static let counterField = "nextDisplayId"

    init(container: CKContainer) {
        self.container = container
        self.database = container.privateCloudDatabase
    }

    /// Allocate the next display ID with optimistic locking.
    /// Retries on conflict up to 5 times.
    func allocateNextID() async throws -> Int {
        var attempts = 0
        let maxAttempts = 5

        while attempts < maxAttempts {
            attempts += 1

            do {
                // Fetch current counter record
                let record: CKRecord
                do {
                    record = try await database.record(for: Self.counterRecordID)
                } catch let error as CKError where error.code == .unknownItem {
                    // First allocation - create counter starting at 2 (allocating 1)
                    return try await createInitialCounter()
                }

                // Read current value and increment
                guard let currentValue = record[Self.counterField] as? Int64 else {
                    throw DisplayIDError.invalidCounterValue
                }

                let allocatedID = Int(currentValue)
                record[Self.counterField] = currentValue + 1

                // Save with optimistic locking
                try await database.save(record)
                return allocatedID

            } catch let error as CKError where error.code == .serverRecordChanged {
                // Conflict - retry with server's version
                continue
            }
        }

        throw DisplayIDError.maxRetriesExceeded
    }

    /// Returns a provisional marker for offline-created tasks.
    func provisionalID() -> DisplayID {
        .provisional
    }

    /// Promote all provisional tasks to permanent IDs.
    /// Sorts by creationDate so display IDs reflect creation order.
    /// Saves after each promotion - partial failure is acceptable.
    func promoteProvisionalTasks(in context: ModelContext) async {
        let predicate = #Predicate<TransitTask> { $0.permanentDisplayId == nil }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.creationDate)]
        )

        guard let provisionalTasks = try? context.fetch(descriptor) else { return }

        for task in provisionalTasks {
            do {
                let id = try await allocateNextID()
                task.permanentDisplayId = id
                try context.save()
            } catch {
                // Stop promoting - remaining tasks retry next time
                // Gaps in display IDs are acceptable per requirements
                break
            }
        }
    }

    // MARK: - Private Helpers

    private func createInitialCounter() async throws -> Int {
        let record = CKRecord(
            recordType: Self.counterRecordType,
            recordID: Self.counterRecordID
        )
        record[Self.counterField] = Int64(2)  // Next ID after allocating 1

        do {
            try await database.save(record)
            return 1  // Allocated the first ID
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Another device created it first - fetch and retry
            let existingRecord = try await database.record(for: Self.counterRecordID)
            guard let currentValue = existingRecord[Self.counterField] as? Int64 else {
                throw DisplayIDError.invalidCounterValue
            }

            let allocatedID = Int(currentValue)
            existingRecord[Self.counterField] = currentValue + 1
            try await database.save(existingRecord)
            return allocatedID
        }
    }
}

enum DisplayIDError: Error, LocalizedError {
    case invalidCounterValue
    case maxRetriesExceeded

    var errorDescription: String? {
        switch self {
        case .invalidCounterValue:
            return "CloudKit counter record has invalid value"
        case .maxRetriesExceeded:
            return "Failed to allocate display ID after maximum retries"
        }
    }
}
