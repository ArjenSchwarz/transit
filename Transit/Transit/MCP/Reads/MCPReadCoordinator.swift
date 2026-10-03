#if os(macOS)
import Foundation

nonisolated struct MCPReadOperation: Sendable {
    let id: UUID
    let generation: UInt64
    private let coordinator: MCPReadCoordinator

    fileprivate init(id: UUID, generation: UInt64, coordinator: MCPReadCoordinator) {
        self.id = id
        self.generation = generation
        self.coordinator = coordinator
    }

    func shouldContinue() -> Bool { coordinator.canContinue(id: id, generation: generation) }

    /// Remaining original admission budget, never a clock restarted by a handler.
    func remainingBudget() -> Duration { coordinator.remainingBudget(id: id, generation: generation) }
}

/// Mutable state is accessed only while holding the injected common publication domain.
nonisolated final class MCPReadCoordinator: @unchecked Sendable {
    private final class Entry: @unchecked Sendable {
        let id: UUID
        let generation: UInt64
        let deadline: ContinuousClock.Instant
        let physicalCompletion: @Sendable () -> Void
        var timeout: Data
        var responseReady = true
        var invalidated = false
        var selected: Data?
        var continuation: CheckedContinuation<Data, Never>?
        var timer: DispatchSourceTimer?

        init(id: UUID, generation: UInt64, deadline: ContinuousClock.Instant, timeout: Data,
             physicalCompletion: @escaping @Sendable () -> Void = {}) {
            self.id = id
            self.generation = generation
            self.deadline = deadline
            self.timeout = timeout
            self.physicalCompletion = physicalCompletion
        }
    }

    let domain: MCPReadPublicationDomain
    private let cutoff: Duration
    private let maxOperations: Int
    private var entries: [UUID: Entry] = [:]
    private var generation: UInt64 = 1
    private var admissionOpen = true
    private let timerQueue = DispatchQueue(label: "transit.read.deadline", qos: .userInitiated, attributes: .concurrent)

    init(domain: MCPReadPublicationDomain = MCPReadPublicationDomain(), cutoff: Duration = .milliseconds(4_850),
         maxOperations: Int = 8) {
        self.domain = domain
        self.cutoff = cutoff
        self.maxOperations = maxOperations
    }

    var unfinishedCount: Int { domain.withLock { entries.count } }

    @concurrent func execute(
        timeout: Data, busy: Data, admittedAt: ContinuousClock.Instant = .now,
        admission: MCPReadAdmission = MCPReadAdmission(),
        worker: @escaping @Sendable (MCPReadOperation) async -> PreparedReadResult
    ) async -> Data {
        let entry = reserve(timeout: timeout, admittedAt: admittedAt, admission: admission)
        guard let entry else { return busy }
        return await executeReserved(entry, worker: worker)
    }

    private func reserve(timeout: Data, admittedAt: ContinuousClock.Instant, admission: MCPReadAdmission) -> Entry? {
        domain.withLock {
            guard admissionOpen, entries.count < maxOperations, entries[admission.operationID] == nil else {
                return nil
            }
            let entry = Entry(id: admission.operationID, generation: generation, deadline: admittedAt + cutoff,
                              timeout: timeout, physicalCompletion: admission.physicalCompletion)
            entries[entry.id] = entry
            return entry
        }
    }

    @concurrent private func executeReserved(
        _ entry: Entry, skipped: (@Sendable () async -> Void)? = nil,
        worker: @escaping @Sendable (MCPReadOperation) async -> PreparedReadResult
    ) async -> Data {
        if Task.isCancelled { expire(entry) }
        let operation = MCPReadOperation(id: entry.id, generation: entry.generation, coordinator: self)
        installTimer(entry)
        Task.detached(priority: .userInitiated) {
            defer { self.physicalFinished(entry.id) }
            await self.prepareAndOffer(operation, skipped: skipped, worker: worker)
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let selected = domain.withLock { () -> Data? in
                    if let selected = entry.selected { return selected }
                    entry.continuation = continuation
                    return nil
                }
                if let selected { continuation.resume(returning: selected) }
            }
        } onCancel: {
            self.expire(entry)
        }
    }

    /// Release the prepared result and its buffers before physical finalization/receipt.
    private func prepareAndOffer(
        _ operation: MCPReadOperation, skipped: (@Sendable () async -> Void)?,
        worker: @escaping @Sendable (MCPReadOperation) async -> PreparedReadResult
    ) async {
        guard operation.shouldContinue() else {
            await skipped?()
            return
        }
        let prepared = await worker(operation)
        offer(prepared, for: operation.id)
    }

    func stop() {
        let completions = domain.withLock { () -> [(CheckedContinuation<Data, Never>, Data)] in
            admissionOpen = false
            generation &+= 1
            return entries.values.compactMap { entry in
                entry.invalidated = true
                return entry.responseReady ? selectLocked(entry.timeout, entry: entry) : nil
            }
        }
        for (continuation, data) in completions { continuation.resume(returning: data) }
    }

    func start() {
        domain.withLock {
            generation &+= 1
            admissionOpen = true
        }
    }

    fileprivate func canContinue(id: UUID, generation: UInt64) -> Bool {
        domain.withLock {
            guard let entry = entries[id] else { return false }
            return admissionOpen && self.generation == generation && entry.responseReady && !entry.invalidated
                && entry.selected == nil && .now < entry.deadline
        }
    }

    fileprivate func remainingBudget(id: UUID, generation: UInt64) -> Duration {
        domain.withLock {
            guard let entry = entries[id], admissionOpen, self.generation == generation,
                  !entry.invalidated, entry.selected == nil else { return .zero }
            return max(.zero, ContinuousClock.now.duration(to: entry.deadline))
        }
    }

    private func installTimer(_ entry: Entry) {
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        let remaining = max(0, seconds(ContinuousClock.now.duration(to: entry.deadline)))
        timer.schedule(deadline: .now() + remaining, leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in self?.expire(entry) }
        domain.withLock {
            if entry.selected == nil { entry.timer = timer } else { timer.cancel() }
        }
        timer.resume()
    }

    private func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    private func expire(_ entry: Entry) {
        let completion = domain.withLock { () -> (CheckedContinuation<Data, Never>, Data)? in
            guard entries[entry.id] === entry else { return nil }
            entry.invalidated = true
            return entry.responseReady ? selectLocked(entry.timeout, entry: entry) : nil
        }
        if let (continuation, data) = completion { continuation.resume(returning: data) }
    }

    private func selectLocked(_ data: Data, entry: Entry) -> (CheckedContinuation<Data, Never>, Data)? {
        guard entry.selected == nil else { return nil }
        entry.selected = data
        entry.timer?.cancel()
        entry.timer = nil
        guard let continuation = entry.continuation else { return nil }
        entry.continuation = nil
        return (continuation, data)
    }

    private func offer(_ prepared: PreparedReadResult, for id: UUID) {
        let distinctStores = Set(prepared.publications.map(\.publicationStoreID))
        let (completion, retired) = domain.withLockRetainingRetirement {
            () -> (CheckedContinuation<Data, Never>, Data)? in
            guard let entry = entries[id], admissionOpen, entry.generation == generation,
                  entry.selected == nil, .now < entry.deadline else {
                for publication in prepared.publications { publication.discardLocked(in: domain) }
                if let entry = entries[id] { return selectLocked(entry.timeout, entry: entry) }
                return nil
            }
            let rejection = distinctStores.count != prepared.publications.count ? .busy
                : prepared.publications.compactMap { $0.validateLocked(in: domain) }.first
            if let rejection {
                for publication in prepared.publications { publication.discardLocked(in: domain) }
                let bytes: Data
                switch rejection {
                case .busy: bytes = prepared.publicationErrors.busy
                case .expired: bytes = prepared.publicationErrors.expired
                case .capacity: bytes = prepared.publicationErrors.capacity
                }
                return selectLocked(bytes, entry: entry)
            }
            for publication in prepared.publications { publication.commitLocked(in: domain) }
            return selectLocked(prepared.encodedResponse, entry: entry)
        }
        if let (continuation, data) = completion { continuation.resume(returning: data) }
        withExtendedLifetime(retired) {}
    }

    private func physicalFinished(_ id: UUID) {
        // Removing the entry drops potentially retained data after leaving the domain lock.
        let receipt: (@Sendable () -> Void)? = {
            let (retired, completion) = domain.withLock {
                let entry = entries.removeValue(forKey: id)
                let completion = entry.flatMap { selectLocked($0.timeout, entry: $0) }
                return (entry, completion)
            }
            if let (continuation, data) = completion { continuation.resume(returning: data) }
            return retired?.physicalCompletion
        }()
        receipt?()
    }
}

extension MCPReadCoordinator {
    /// Read-only protocol batch seam. Fixed invalid responses and notifications
    /// retain their positions. Callers coalesce same-store publications while assembling.
    @concurrent func executeBatch(
        _ elements: [MCPReadBatchElement], admittedAt: ContinuousClock.Instant = .now,
        beforeFallbackReady: @escaping @Sendable () async -> Void = {},
        assemble: @escaping @Sendable ([PreparedReadResult?]) async throws -> PreparedReadResult
    ) async -> Data? {
        let admission = admitBatch(elements, admittedAt: admittedAt)
        let admitted = admission.admitted
        await beforeFallbackReady()
        let fallback = MCPReadBatchEncoding.array(admission.fallbackElements)
        guard let first = admitted.first else { return fallback }
        // The complete fallback is ready before any physical dispatch or final assembly.
        readyBatch(first.entry, fallback: fallback ?? Data())
        let collector = MCPReadBatchCollector(values: admission.initial, remaining: admitted.count)
        for admission in admitted.dropFirst() {
            let position = admission.position
            let entry = admission.entry
            let work = admission.work
            Task.detached(priority: .userInitiated) {
                _ = await self.executeReserved(entry, skipped: {
                    let discarded = await collector.complete(position, value: work.responds
                        ? self.fixedResult(work.timeout) : nil)
                    self.discard(discarded)
                }, worker: { operation in
                    let result = operation.shouldContinue()
                        ? await work.worker(operation) : self.fixedResult(work.timeout)
                    if !work.responds { self.discard(result.publications) }
                    let discarded = await collector.complete(position, value: work.responds ? result : nil)
                    self.discard(discarded)
                    return self.fixedResult(result.encodedResponse)
                })
            }
        }
        let selected = await executeReserved(first.entry, skipped: {
            self.discard(await collector.cancel())
        }, worker: { operation in
            let result = operation.shouldContinue()
                ? await first.work.worker(operation) : self.fixedResult(first.work.timeout)
            if !first.work.responds { self.discard(result.publications) }
            let discarded = await collector.complete(first.position, value: first.work.responds ? result : nil)
            self.discard(discarded)
            let completed = await collector.all()
            guard operation.shouldContinue(), fallback != nil else {
                self.discard(completed.compactMap { $0 }.flatMap(\.publications))
                return self.fixedResult(fallback ?? Data())
            }
            do { return try await assemble(completed) } catch {
                self.discard(completed.compactMap { $0 }.flatMap(\.publications))
                return self.fixedResult(fallback ?? Data())
            }
        })
        return fallback == nil ? nil : selected
    }

    private nonisolated struct BatchAdmissions: Sendable {
        let fallbackElements: [Data?]
        let initial: [PreparedReadResult?]
        let admitted: [BatchAdmission]
    }

    private nonisolated struct BatchAdmission: Sendable {
        let position: Int
        let entry: Entry
        let work: MCPReadBatchWork
    }

    private nonisolated func readyBatch(_ entry: Entry, fallback: Data) {
        domain.withLock {
            entry.timeout = fallback
            entry.responseReady = true
            if entry.invalidated || !admissionOpen || entry.generation != generation
                || .now >= entry.deadline {
                _ = selectLocked(entry.timeout, entry: entry)
            }
        }
    }

    private nonisolated func admitBatch(
        _ elements: [MCPReadBatchElement], admittedAt: ContinuousClock.Instant
    ) -> BatchAdmissions {
        let reads = elements.enumerated().compactMap { position, element -> (Int, MCPReadBatchWork)? in
            guard case .read(let work) = element else { return nil }
            return (position, work)
        }
        // Only up to eight compact entries are allocated under the domain; bulk
        // fallback arrays and index construction stay outside this critical section.
        let admitted = domain.withLock { () -> [BatchAdmission] in
            guard admissionOpen else { return [] }
            return reads.prefix(max(0, maxOperations - entries.count)).enumerated().map { index, read in
                let entry = Entry(id: UUID(), generation: generation, deadline: admittedAt + cutoff,
                                  timeout: read.1.timeout)
                entry.responseReady = index != 0
                entries[entry.id] = entry
                return BatchAdmission(position: read.0, entry: entry, work: read.1)
            }
        }
        let admittedPositions = Set(admitted.map(\.position))
        var fallbackElements: [Data?] = []
        var initial: [PreparedReadResult?] = []
        for (position, element) in elements.enumerated() {
            switch element {
            case .fixed(let bytes):
                fallbackElements.append(bytes)
                initial.append(bytes.map { fixedResult($0) })
            case .read(let work):
                if admittedPositions.contains(position) {
                    fallbackElements.append(work.responds ? work.timeout : nil)
                    initial.append(nil)
                } else {
                    fallbackElements.append(work.responds ? work.busy : nil)
                    initial.append(work.responds ? fixedResult(work.busy) : nil)
                }
            }
        }
        return BatchAdmissions(fallbackElements: fallbackElements, initial: initial, admitted: admitted)
    }

    private nonisolated func fixedResult(_ bytes: Data) -> PreparedReadResult {
        PreparedReadResult(encodedResponse: bytes, publications: [],
                           publicationErrors: PreencodedPublicationErrors(busy: bytes, expired: bytes, capacity: bytes))
    }

    private nonisolated func discard(_ publications: [any MCPPreparedPublication]) {
        domain.withLock { for publication in publications { publication.discardLocked(in: domain) } }
    }
}
#endif
