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
        /// The live `ModelContainer` was created with `cloudKitDatabase: .none`, so the
        /// CloudKit counter record is off limits (T-1797). Callers treat this like any
        /// other allocation failure and fall back to a provisional ID.
        case cloudSyncInactive
        /// The caller's `excluding:` snapshot of already-used display IDs could not be
        /// read, so the collision guard cannot be evaluated (T-1621). Distinct from the
        /// CloudKit failures above because it means the *local* store is unreadable:
        /// callers must not treat it as an offline condition and fall back to a
        /// provisional ID. The description carries the underlying storage error.
        case usedIDLookupFailed(description: String)
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

    /// Whether the live `ModelContainer` is CloudKit-backed. The display-ID counter lives
    /// in SwiftData's CloudKit zone, so when the container was created with
    /// `cloudKitDatabase: .none` the counter must not be read or written at all —
    /// allocation and promotion no-op and provisional IDs accumulate until the user
    /// re-enables sync and relaunches (T-1797).
    ///
    /// Fixed at construction because SwiftData fixes the container's CloudKit mode at
    /// launch; flipping the Settings toggle does not change what the live container does
    /// (T-1857). Callers that need to skip work entirely — rather than catch the thrown
    /// `.cloudSyncInactive` — can read this directly.
    let isCloudSyncActive: Bool

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
    private let allocationGate: AllocationGate

    /// IDs this process has already handed out but whose owners may not yet have
    /// committed them to the local store. The caller's `usedIDs` closure only
    /// reflects *committed* records, but the commit happens after `allocateNextID`
    /// returns and the gate is released — so against a stuck/stale counter a later
    /// caller could otherwise re-read and re-issue an ID that an earlier caller
    /// allocated but has not yet saved. Tracking issued IDs in-process closes that
    /// window (T-1395). Only mutated while holding the gate, on @MainActor.
    private var issuedIDs: Set<Int> = []

    init(
        store: CounterStore,
        retryLimit: Int = 5,
        isCloudSyncActive: Bool = true,
        onWaiterQueued: (@Sendable () -> Void)? = nil,
        onWaiterCancelled: (@Sendable () -> Void)? = nil
    ) {
        self.counterStore = store
        self.retryLimit = max(1, retryLimit)
        self.isCloudSyncActive = isCloudSyncActive
        self.allocationGate = AllocationGate(
            onWaiterQueued: onWaiterQueued,
            onWaiterCancelled: onWaiterCancelled
        )
    }

    convenience init(
        container: CKContainer = .default(),
        counterRecordName: String = "global-counter",
        retryLimit: Int = 5,
        isCloudSyncActive: Bool = true
    ) {
        self.init(
            store: CloudKitCounterStore(
                database: container.privateCloudDatabase,
                recordName: counterRecordName
            ),
            retryLimit: retryLimit,
            isCloudSyncActive: isCloudSyncActive
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
    ///
    /// Throws `.cloudSyncInactive` immediately — before the gate and before any store
    /// access — when the live container is not CloudKit-backed (T-1797).
    ///
    /// `usedIDs` is allowed to throw. A storage failure there means the guard cannot be
    /// evaluated at all, so allocation fails with `.usedIDLookupFailed` rather than
    /// proceeding against an empty set that would silently disable it (T-1621).
    func allocateNextID(
        excluding usedIDs: @MainActor @Sendable () throws -> Set<Int> = { [] }
    ) async throws -> Int {
        guard isCloudSyncActive else { throw Error.cloudSyncInactive }
        return try await allocationGate.run {
            try await self.allocateLocked(excluding: usedIDs)
        }
    }

    /// The actual allocation loop. Only ever runs while the caller holds the
    /// allocation gate, so reads and CAS writes do not interleave with another
    /// in-process allocation. The `usedIDs` snapshot is recomputed on every
    /// attempt inside the gate so it always reflects the latest committed state.
    private func allocateLocked(
        excluding usedIDs: @MainActor @Sendable () throws -> Set<Int>
    ) async throws -> Int {
        var attempt = 0
        while attempt < retryLimit {
            attempt += 1

            let snapshot = try await counterStore.loadCounter()
            let candidate = snapshot.nextDisplayID
            // Combine committed IDs (from the caller) with IDs this process has
            // already issued but not yet observed committed, so neither a stale
            // counter read nor the allocate→commit gap can yield a duplicate.
            let committed: Set<Int>
            do {
                committed = try await usedIDs()
            } catch {
                // Without the snapshot the collision guard below is meaningless, so
                // fail the allocation instead of returning a candidate we could not
                // check (T-1621).
                throw Error.usedIDLookupFailed(description: "\(error)")
            }
            let used = committed.union(issuedIDs)

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
    /// after the permanent ID has been assigned in memory. `usedTaskIDs` is
    /// injectable for tests that need to simulate an unreadable local store
    /// (T-1621); it defaults to reading the committed IDs from `context`.
    func promoteProvisionalTasks(
        in context: ModelContext,
        usedTaskIDs: (@MainActor @Sendable () throws -> Set<Int>)? = nil,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) async {
        // Scene activation and connectivity restore both call this unconditionally; with
        // sync off there is nothing to promote to, so bail before even fetching (T-1797).
        guard isCloudSyncActive else { return }
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

        // Exclude IDs already committed locally (recomputed inside the gate on
        // every attempt so just-promoted IDs are included) so promotion never
        // assigns a duplicate (T-1395). A failed read throws rather than yielding
        // an empty set, which would disable the guard entirely (T-1621).
        let usedIDs = usedTaskIDs ?? { try UsedDisplayIDs(context).tasks() }
        let recordLookup = DisplayIDRecordLookup(modelContext: context)

        for task in tasks {
            let newID: Int
            do {
                newID = try await allocateNextID(excluding: usedIDs)
                // Allocation suspends, so re-read committed state through a transient
                // context before mutating the stale registered object (T-2020).
                // Missing or unreadable records fail closed.
                guard try recordLookup.taskIsStillProvisional(id: task.id) else {
                    // The allocated counter value cannot be reused safely; another
                    // record may already have observed it, so deliberately leave a gap.
                    continue
                }
            } catch {
                // Stop on allocation or committed-state read failure. Remaining
                // tasks will be retried by the next lifecycle promotion pass.
                break
            }

            task.permanentDisplayId = newID
            do {
                try save(context)
            } catch {
                // Revert only the value this promotion assigned. If SwiftData merged
                // a peer value, preserve it rather than resetting the record to nil.
                if task.permanentDisplayId == newID {
                    task.permanentDisplayId = nil
                }
                break
            }
        }
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
    /// Test-only lifecycle observers make the queued-cancellation regression
    /// deterministic. Production callers leave both nil.
    private let onWaiterQueued: (@Sendable () -> Void)?
    private let onWaiterCancelled: (@Sendable () -> Void)?
    /// FIFO queue of suspended callers, keyed by a monotonically increasing id so
    /// a cancelled caller can locate and remove its own continuation without
    /// disturbing arrival order. `Bool` is the acquisition outcome handed to the
    /// resumed waiter: `true` means it now holds the lock, `false` means it was
    /// cancelled out of the queue and does NOT hold the lock.
    private var waiters: [(id: UInt64, continuation: CheckedContinuation<Bool, Never>)] = []
    private var nextWaiterID: UInt64 = 0

    init(
        onWaiterQueued: (@Sendable () -> Void)? = nil,
        onWaiterCancelled: (@Sendable () -> Void)? = nil
    ) {
        self.onWaiterQueued = onWaiterQueued
        self.onWaiterCancelled = onWaiterCancelled
    }

    /// Runs `body` while holding the lock. Other callers queue until it returns.
    ///
    /// Cancellation is checked after acquisition, before `body` starts. That
    /// closes the two windows the waiter-queue handling below does not cover: a
    /// caller that is already cancelled when it takes an uncontended lock, and a
    /// caller that is cancelled while `release()` is handing it the lock (T-1765).
    /// The check deliberately sits *after* `acquire()` — an equivalent pre-acquire
    /// check would be redundant (both windows still end in this check) and would
    /// stop cancelled callers from ever reaching the waiter queue, leaving the
    /// queued-waiter path below untestable.
    ///
    /// Acquisition is cancellation-aware: if the calling Task is cancelled while
    /// suspended in the waiter queue, its continuation is removed and resumed
    /// rather than left pending (which would otherwise trip the runtime's
    /// "continuation leaked" check on teardown). A waiter that is cancelled out of
    /// the queue never held the lock, so `run` throws `CancellationError` without
    /// calling `release` — the lock is never lost. If cancellation races and loses
    /// (the lock was already handed to this waiter via `release`), the post-acquire
    /// check observes it, and `defer` still releases the lock without running `body`.
    func run<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        let acquired = await acquire()
        guard acquired else { throw CancellationError() }
        defer { release() }
        try Task.checkCancellation()
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
                onWaiterQueued?()
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
        onWaiterCancelled?()
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
