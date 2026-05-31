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

    /// Exposed so callers that need direct counter access (e.g. `DisplayIDMaintenanceService`'s
    /// counter-advance fence) can use the same store the allocator uses. Tests inject an in-memory
    /// store via `init(store:retryLimit:)`.
    let counterStore: CounterStore
    private let retryLimit: Int

    /// Single-flight guard for `promoteProvisionalTasks`. Prevents concurrent
    /// promotion runs from overlapping (T-597). Must only be accessed from
    /// @MainActor callers — the compiler does not enforce this because the
    /// class is @unchecked Sendable.
    private var isPromotingTasks = false

    /// Serialises `allocateNextID` so two concurrent callers cannot interleave
    /// their load→compare-and-swap cycles (T-1395). Without this, re-entrant
    /// `async` allocations (e.g. overlapping MCP/intent task creates suspending
    /// at the CloudKit `await`) all read the same counter snapshot, then fight
    /// over the same CAS — burning the retry budget and, against an eventually
    /// consistent counter read, risking duplicate IDs. The gate makes allocation
    /// strictly sequential within the process; cross-process safety still relies
    /// on the CounterStore's compare-and-swap.
    ///
    /// Must only be accessed from @MainActor callers (see note above).
    private var allocationGate: AllocationGate = .init()

    /// IDs this process has already handed out but whose owners may not yet have
    /// committed them to the local store. The caller's `usedIDs` closure only
    /// reflects *committed* records, but the commit happens after `allocateNextID`
    /// returns and the gate is released — so against a stuck/stale counter a later
    /// caller could otherwise re-read and re-issue an ID that an earlier caller
    /// allocated but has not yet saved. Tracking issued IDs in-process closes that
    /// window (T-1395). Only mutated while holding the gate, on @MainActor.
    private var issuedIDs: Set<Int> = []

    init(store: CounterStore, retryLimit: Int = 5) {
        self.counterStore = store
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
    ///
    /// `usedIDs` is a closure returning the set of display IDs already known to
    /// be in use locally (e.g. committed tasks/milestones). It is evaluated
    /// **inside** the allocation gate, so each caller sees a snapshot taken
    /// after the previous holder has committed its allocation — not a stale one
    /// captured before queueing. When the counter hands back an ID that collides
    /// with this set — which can happen if a peer device or a concurrent process
    /// already consumed it and our counter read was stale — the counter is
    /// advanced past the collision and allocation is retried so a duplicate ID is
    /// never returned (T-1395).
    ///
    /// Allocation is serialised in-process via `allocationGate` so concurrent
    /// callers run their load→CAS cycles one at a time.
    func allocateNextID(excluding usedIDs: @MainActor @Sendable () -> Set<Int> = { [] }) async throws -> Int {
        try await allocationGate.run {
            try await self.allocateLocked(excluding: usedIDs)
        }
    }

    /// The actual allocation loop. Only ever runs while the caller holds the
    /// allocation gate, so reads and CAS writes do not interleave with another
    /// in-process allocation. The `usedIDs` snapshot is recomputed on every
    /// attempt inside the gate so it always reflects the latest committed state.
    private func allocateLocked(excluding usedIDs: @MainActor @Sendable () -> Set<Int>) async throws -> Int {
        var attempt = 0
        while attempt < retryLimit {
            attempt += 1

            let snapshot = try await counterStore.loadCounter()
            let candidate = snapshot.nextDisplayID
            // Combine committed IDs (from the caller) with IDs this process has
            // already issued but not yet observed committed, so neither a stale
            // counter read nor the allocate→commit gap can yield a duplicate.
            let used = await usedIDs().union(issuedIDs)

            // If the counter points at an ID that is already in use, skip past
            // the whole occupied range in one CAS instead of handing back a
            // duplicate.
            if used.contains(candidate) {
                var advancedTo = candidate + 1
                while used.contains(advancedTo) { advancedTo += 1 }
                do {
                    try await counterStore.saveCounter(
                        nextDisplayID: advancedTo,
                        expectedChangeTag: snapshot.changeTag
                    )
                } catch let error as Error where error == .conflict {
                    // Another writer moved the counter; re-read and try again.
                }
                continue
            }

            do {
                try await counterStore.saveCounter(
                    nextDisplayID: candidate + 1,
                    expectedChangeTag: snapshot.changeTag
                )
                issuedIDs.insert(candidate)
                return candidate
            } catch let error as Error where error == .conflict {
                continue
            }
        }

        throw Error.retriesExhausted
    }

    /// Finds tasks with provisional display IDs (permanentDisplayId == nil),
    /// sorts them by creation date, and allocates permanent IDs one at a time.
    /// `save` is injectable for tests that need to simulate a save failure
    /// after the permanent ID has been assigned in memory.
    func promoteProvisionalTasks(
        in context: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) async {
        guard !isPromotingTasks else { return }
        isPromotingTasks = true
        defer { isPromotingTasks = false }

        let descriptor = FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.permanentDisplayId == nil },
            sortBy: [SortDescriptor(\.creationDate, order: .forward)]
        )

        guard let tasks = try? context.fetch(descriptor), !tasks.isEmpty else {
            return
        }

        for task in tasks {
            do {
                // Exclude IDs already committed locally (recomputed inside the
                // gate so just-promoted IDs are included) so promotion never
                // assigns a duplicate (T-1395).
                let newID = try await allocateNextID(excluding: { Self.usedTaskDisplayIDs(in: context) })
                task.permanentDisplayId = newID
                try save(context)
            } catch {
                // Revert only this promotion attempt so unrelated unsaved edits
                // on the shared context survive connectivity-triggered retries.
                task.permanentDisplayId = nil
                // Stop on first failure -- remaining tasks will be retried next pass.
                break
            }
        }
    }

    /// Permanent task display IDs already committed to `context`. Used to keep
    /// promotion allocations collision-free (T-1395). Failures degrade to an
    /// empty set so promotion still proceeds.
    private static func usedTaskDisplayIDs(in context: ModelContext) -> Set<Int> {
        let descriptor = FetchDescriptor<TransitTask>(
            predicate: #Predicate { $0.permanentDisplayId != nil }
        )
        guard let tasks = try? context.fetch(descriptor) else { return [] }
        return Set(tasks.compactMap(\.permanentDisplayId))
    }
}

// MARK: - Allocation serialisation

/// A FIFO async mutex used to serialise display-ID allocation within a process.
///
/// `allocateNextID` is `async` and suspends at the CloudKit `await`, so without
/// a gate two overlapping callers would both read the same counter snapshot
/// before either writes it back. This actor admits one `run` body at a time and
/// hands the lock to waiters in arrival order, so allocations execute strictly
/// sequentially even when many callers race.
private actor AllocationGate {
    private var isLocked = false
    /// FIFO queue of suspended callers, keyed by a monotonically increasing id so
    /// a cancelled caller can locate and remove its own continuation without
    /// disturbing arrival order. `Bool` is the acquisition outcome handed to the
    /// resumed waiter: `true` means it now holds the lock, `false` means it was
    /// cancelled out of the queue and does NOT hold the lock.
    private var waiters: [(id: UInt64, continuation: CheckedContinuation<Bool, Never>)] = []
    private var nextWaiterID: UInt64 = 0

    /// Runs `body` while holding the lock. Other callers queue until it returns.
    ///
    /// Acquisition is cancellation-aware: if the calling Task is cancelled while
    /// suspended in the waiter queue, its continuation is removed and resumed
    /// rather than left pending (which would otherwise trip the runtime's
    /// "continuation leaked" check on teardown). A waiter that is cancelled out of
    /// the queue never held the lock, so `run` throws `CancellationError` without
    /// calling `release` — the lock is never lost. If cancellation races and loses
    /// (the lock was already handed to this waiter via `release`), the waiter keeps
    /// the lock, runs `body`, and releases normally.
    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        let acquired = await acquire()
        guard acquired else { throw CancellationError() }
        defer { release() }
        return try await body()
    }

    /// Returns `true` once this caller holds the lock, or `false` if it was
    /// cancelled while queued (in which case it does not hold the lock).
    private func acquire() async -> Bool {
        if !isLocked {
            isLocked = true
            return true
        }
        let id = nextWaiterID
        nextWaiterID += 1
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters.append((id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    /// Removes a still-queued waiter on cancellation and resumes it with `false`
    /// so it learns it does not hold the lock. If the waiter has already been
    /// handed the lock by `release()` it is no longer in the queue and this is a
    /// no-op — the waiter keeps the lock and releasing it stays correct.
    private func cancelWaiter(id: UInt64) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(returning: false)
    }

    private func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            // Hand the lock directly to the next waiter (stays locked).
            let next = waiters.removeFirst()
            next.continuation.resume(returning: true)
        }
    }
}

// MARK: - CounterStore advance

extension DisplayIDAllocator.CounterStore {
    /// Advances the counter so that `nextDisplayID` is at least `target`.
    /// No-op when the counter is already at or past `target`. Uses
    /// compare-and-swap via `saveCounter`, retrying on conflict so a racing
    /// writer that already moved the counter past `target` short-circuits the
    /// loop on the next `loadCounter` read.
    func advanceCounter(toAtLeast target: Int, retryLimit: Int = 5) async throws {
        var attempt = 0
        while attempt < retryLimit {
            attempt += 1
            let snapshot = try await loadCounter()
            if snapshot.nextDisplayID >= target { return }
            do {
                try await saveCounter(nextDisplayID: target, expectedChangeTag: snapshot.changeTag)
                return
            } catch let error as DisplayIDAllocator.Error where error == .conflict {
                continue
            }
        }
        throw DisplayIDAllocator.Error.retriesExhausted
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
