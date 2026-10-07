import Foundation

/// Mutable state is accessed only while holding the injected common publication domain.
nonisolated final class MCPReadCoordinator: @unchecked Sendable {
    let domain: MCPReadPublicationDomain
    let diagnostics: MCPReadDiagnosticSink
    private let cutoff: Duration
    private let maxOperations: Int
    private var entries: [UUID: Entry] = [:]
    private var generation: UInt64 = 1
    private var admissionOpen = true
    private var activeListener: UUID?
    private let timerQueue = DispatchQueue(label: "transit.read.deadline", qos: .userInitiated, attributes: .concurrent)

    init(domain: MCPReadPublicationDomain = MCPReadPublicationDomain(), cutoff: Duration = .milliseconds(4_850),
         maxOperations: Int = 8, diagnostics: MCPReadDiagnosticSink = .disabled) {
        self.domain = domain
        self.cutoff = cutoff
        self.maxOperations = maxOperations
        self.diagnostics = diagnostics
    }

    var unfinishedCount: Int { domain.withLock { entries.count } }

    @concurrent func execute(
        timeout: Data, busy: Data, admittedAt: ContinuousClock.Instant = .now,
        admission: MCPReadAdmission = MCPReadAdmission(),
        diagnosticTool: String = "unknown",
        worker: @escaping @Sendable (MCPReadOperation) async -> PreparedReadResult
    ) async -> Data {
        let entry = reserve(timeout: timeout, admittedAt: admittedAt, admission: admission, tool: diagnosticTool)
        guard let entry else { return busy }
        return await executeReserved(entry, worker: worker)
    }

    private func reserve(timeout: Data, admittedAt: ContinuousClock.Instant, admission: MCPReadAdmission,
                         tool: String) -> Entry? {
        var rejected: MCPReadDiagnosticContext?
        let entry = domain.withLock { () -> Entry? in
            guard admissionOpen, admission.owner.isActive(listener: activeListener), entries.count < maxOperations,
                  entries[admission.operationID] == nil else {
                if diagnostics.capacity > 0 {
                    rejected = MCPReadDiagnosticContext(operationID: admission.operationID, tool: tool,
                        generation: generation, admittedAt: admittedAt, responseDeadline: admittedAt + .seconds(5),
                        internalCutoff: admittedAt + cutoff)
                }
                return nil
            }
            let entry = Entry(id: admission.operationID, generation: generation, deadline: admittedAt + cutoff,
                              timeout: timeout, admittedAt: admittedAt, diagnosticTool: tool, owner: admission.owner,
                              physicalCompletion: admission.physicalCompletion)
            entries[entry.id] = entry
            return entry
        }
        if let rejected { recordDiagnostic(context: rejected, phase: .terminal,
                                            startedAt: admittedAt, outcome: .busy) }
        return entry
    }

    @concurrent private func executeReserved(
        _ entry: Entry, skipped: (@Sendable () async -> Void)? = nil,
        worker: @escaping @Sendable (MCPReadOperation) async -> PreparedReadResult
    ) async -> Data {
        if Task.isCancelled { expire(entry) }
        let operation = MCPReadOperation(id: entry.id, generation: entry.generation,
                                         context: entry.diagnosticContext, coordinator: self)
        installTimer(entry)
        let operationID = entry.id
        Task.detached(priority: .userInitiated) {
            defer { self.physicalFinished(operationID) }
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
        operation.recordDiagnostic(.queue, startedAt: operation.diagnosticContext.admittedAt)
        guard operation.shouldContinue() else {
            let started = ContinuousClock.now
            await skipped?()
            operation.recordDiagnostic(.discard, startedAt: started, outcome: .discarded)
            return
        }
        let prepared = await worker(operation)
        offer(prepared, for: operation.id)
    }

    func changeLifecycle(_ change: MCPReadLifecycleChange) {
        let (stopped, completions) = domain.withLock { () -> ([Entry], [(CheckedContinuation<Data, Never>, Data)]) in
            let stopped: [Entry]
            switch change {
            case .stopApplication:
                admissionOpen = false
                activeListener = nil
                generation &+= 1
                stopped = Array(entries.values)
            case .startApplication:
                admissionOpen = true
                generation &+= 1
                stopped = []
            case .startListener(let id):
                let previous = activeListener
                activeListener = id
                stopped = previous == id ? [] : entries.values.filter {
                    $0.owner == previous.map(MCPReadAdmissionOwner.listener)
                }
            case .stopListener(let id):
                if activeListener == id { activeListener = nil }
                stopped = entries.values.filter { $0.owner == .listener(id) }
            }
            let completions = stopped.compactMap { entry in
                entry.invalidated = true
                return entry.responseReady ? selectLocked(entry.timeout, entry: entry) : nil
            }
            return (stopped, completions)
        }
        for (continuation, data) in completions { continuation.resume(returning: data) }
        for entry in stopped { flushTerminal(entry) }
    }

    func canContinue(id: UUID, generation: UInt64) -> Bool {
        domain.withLock {
            guard let entry = entries[id] else { return false }
            return admissionOpen && self.generation == generation && entry.responseReady && !entry.invalidated
                && entry.selected == nil && .now < entry.deadline
        }
    }

    func remainingBudget(id: UUID, generation: UInt64) -> Duration {
        domain.withLock {
            guard let entry = entries[id], admissionOpen, self.generation == generation,
                  !entry.invalidated, entry.selected == nil else { return .zero }
            return max(.zero, ContinuousClock.now.duration(to: entry.deadline))
        }
    }

    private func installTimer(_ entry: Entry) {
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        let remaining = max(0, MCPReadTiming.seconds(ContinuousClock.now.duration(to: entry.deadline)))
        timer.schedule(deadline: .now() + remaining, leeway: .nanoseconds(0))
        timer.setEventHandler { [weak self] in self?.expire(entry) }
        domain.withLock {
            if entry.selected == nil { entry.timer = timer } else { timer.cancel() }
        }
        timer.resume()
    }

    private func expire(_ entry: Entry) {
        let completion = domain.withLock { () -> (CheckedContinuation<Data, Never>, Data)? in
            guard entries[entry.id] === entry else { return nil }
            entry.invalidated = true
            return entry.responseReady ? selectLocked(entry.timeout, entry: entry) : nil
        }
        if let (continuation, data) = completion { continuation.resume(returning: data) }
        flushTerminal(entry)
    }

    private func selectLocked(_ data: Data, entry: Entry, outcome: MCPReadDiagnosticOutcome? = .timeout)
        -> (CheckedContinuation<Data, Never>, Data)? {
        guard entry.selected == nil else { return nil }
        entry.selected = data
        if diagnostics.capacity > 0 {
            entry.terminalEvent = MCPReadDiagnosticEvent(context: entry.diagnosticContext, phase: .terminal,
                startedAt: entry.diagnosticContext.admittedAt, finishedAt: .now, outcome: outcome,
                unfinishedPhysicalCount: entries.count)
        }
        entry.timer?.cancel()
        entry.timer = nil
        guard let continuation = entry.continuation else { return nil }
        entry.continuation = nil
        return (continuation, data)
    }

    private func offer(_ prepared: PreparedReadResult, for id: UUID) {
        let distinctStores = Set(prepared.publications.map(\.publicationStoreID))
        let offerStarted = ContinuousClock.now
        var selectedEntry: Entry?
        var late = false
        let (completion, retired) = domain.withLockRetainingRetirement {
            () -> (CheckedContinuation<Data, Never>, Data)? in
            selectedEntry = entries[id]
            guard let entry = selectedEntry, admissionOpen, entry.generation == generation,
                  entry.selected == nil, .now < entry.deadline else {
                late = true
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
                return selectLocked(bytes, entry: entry, outcome: rejection == .busy ? .busy : .failure)
            }
            for publication in prepared.publications { publication.commitLocked(in: domain) }
            return selectLocked(prepared.encodedResponse, entry: entry, outcome: prepared.diagnosticOutcome)
        }
        if let (continuation, data) = completion { continuation.resume(returning: data) }
        withExtendedLifetime(retired) {}
        recordOffer(entry: selectedEntry, late: late, startedAt: offerStarted)
    }

    private func recordOffer(entry: Entry?, late: Bool, startedAt: ContinuousClock.Instant) {
        guard let entry else { return }
        flushTerminal(entry)
        if late { recordDiagnostic(context: entry.diagnosticContext, phase: .discard,
                                   startedAt: startedAt, outcome: .discarded) }
    }

    private func physicalFinished(_ id: UUID) {
        let started = ContinuousClock.now
        let receipt: ((@Sendable () -> Void), MCPReadDiagnosticContext)? = {
            let (retired, completion) = domain.withLock {
                let entry = entries.removeValue(forKey: id)
                let completion = entry.flatMap { selectLocked($0.timeout, entry: $0) }
                return (entry, completion)
            }
            if let (continuation, data) = completion { continuation.resume(returning: data) }
            guard let retired else { return nil }
            flushTerminal(retired)
            return (retired.physicalCompletion, retired.diagnosticContext)
        }()
        // Entry buffers and worker/private cleanup are released before this event and receipt.
        if let (completion, context) = receipt {
            recordDiagnostic(context: context, phase: .physicalFinish, startedAt: started)
            completion()
        }
    }

    private func flushTerminal(_ entry: Entry) {
        guard diagnostics.capacity > 0 else { return }
        let event = domain.withLock { () -> MCPReadDiagnosticEvent? in
            guard !entry.terminalDelivered, let event = entry.terminalEvent else { return nil }
            entry.terminalDelivered = true
            return event
        }
        if let event { diagnostics.enqueue(event) }
    }

    func beginActorQueue(id: UUID) {
        guard diagnostics.capacity > 0 else { return }
        domain.withLock { entries[id]?.actorQueuedAt = .now }
    }

    func finishActorQueue(id: UUID) {
        guard diagnostics.capacity > 0 else { return }
        let interval = domain.withLock { () -> (MCPReadDiagnosticContext, ContinuousClock.Instant)? in
            guard let entry = entries[id], let started = entry.actorQueuedAt else { return nil }
            entry.actorQueuedAt = nil
            return (entry.diagnosticContext, started)
        }
        if let (context, started) = interval { recordDiagnostic(context: context, phase: .queue, startedAt: started) }
    }
}

#if os(macOS)
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
                        ? MCPReadBatchUtilities.result(work.timeout) : nil)
                    MCPReadBatchUtilities.discard(discarded, in: self.domain)
                }, worker: { operation in
                    let result = operation.shouldContinue()
                        ? await work.worker(operation) : MCPReadBatchUtilities.result(work.timeout)
                    if !work.responds { MCPReadBatchUtilities.discard(result.publications, in: self.domain) }
                    let discarded = await collector.complete(position, value: work.responds ? result : nil)
                    MCPReadBatchUtilities.discard(discarded, in: self.domain)
                    return MCPReadBatchUtilities.result(result.encodedResponse)
                })
            }
        }
        let selected = await executeReserved(first.entry, skipped: {
            MCPReadBatchUtilities.discard(await collector.cancel(), in: self.domain)
        }, worker: { operation in
            let result = operation.shouldContinue()
                ? await first.work.worker(operation) : MCPReadBatchUtilities.result(first.work.timeout)
            if !first.work.responds { MCPReadBatchUtilities.discard(result.publications, in: self.domain) }
            let discarded = await collector.complete(first.position, value: first.work.responds ? result : nil)
            MCPReadBatchUtilities.discard(discarded, in: self.domain)
            let completed = await collector.all()
            guard operation.shouldContinue(), fallback != nil else {
                MCPReadBatchUtilities.discard(completed.compactMap { $0 }.flatMap(\.publications), in: self.domain)
                return MCPReadBatchUtilities.result(fallback ?? Data())
            }
            let assemblyStarted = ContinuousClock.now
            defer { operation.recordDiagnostic(.aggregation, startedAt: assemblyStarted) }
            do { return try await assemble(completed) } catch {
                MCPReadBatchUtilities.discard(completed.compactMap { $0 }.flatMap(\.publications), in: self.domain)
                return MCPReadBatchUtilities.result(fallback ?? Data())
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
                                  timeout: read.1.timeout, admittedAt: admittedAt, diagnosticTool: "historical_batch")
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
                initial.append(bytes.map { MCPReadBatchUtilities.result($0) })
            case .read(let work):
                if admittedPositions.contains(position) {
                    fallbackElements.append(work.responds ? work.timeout : nil)
                    initial.append(nil)
                } else {
                    fallbackElements.append(work.responds ? work.busy : nil)
                    initial.append(work.responds ? MCPReadBatchUtilities.result(work.busy) : nil)
                }
            }
        }
        return BatchAdmissions(fallbackElements: fallbackElements, initial: initial, admitted: admitted)
    }

}
#endif
