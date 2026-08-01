import Foundation
import SwiftData

/// Scans for tasks/milestones sharing a `permanentDisplayId` and reassigns
/// fresh IDs to losers in each duplicate group. See `specs/duplicate-displayid-cleanup`
/// for the design.
@MainActor @Observable
// swiftlint:disable:next type_body_length
final class DisplayIDMaintenanceService {

    private let modelContext: ModelContext
    private let taskAllocator: DisplayIDAllocator
    private let milestoneAllocator: DisplayIDAllocator
    private let commentService: CommentService
    private let clock: () -> Date
    private let lookup: DisplayIDRecordLookup
    private let usedDisplayIDs: UsedDisplayIDs

    /// Single-flight guard for `reassignDuplicates`. Mutated only on @MainActor.
    private var isReassigning = false

    init(
        modelContext: ModelContext,
        taskAllocator: DisplayIDAllocator,
        milestoneAllocator: DisplayIDAllocator,
        commentService: CommentService,
        clock: @escaping () -> Date = { Date.now }
    ) {
        self.modelContext = modelContext
        self.taskAllocator = taskAllocator
        self.milestoneAllocator = milestoneAllocator
        self.commentService = commentService
        self.clock = clock
        self.lookup = DisplayIDRecordLookup(modelContext: modelContext)
        self.usedDisplayIDs = UsedDisplayIDs(modelContext)
    }

    // MARK: - Scan

    /// Returns a report of tasks and milestones sharing `permanentDisplayId`.
    /// Two `FetchDescriptor` reads, client-side group-by, deterministic winner.
    func scanDuplicates() throws -> DuplicateReport {
        let tasks = try modelContext.fetch(FetchDescriptor<TransitTask>())
        let milestones = try modelContext.fetch(FetchDescriptor<Milestone>())

        let taskGroups = groupTasks(tasks)
        let milestoneGroups = groupMilestones(milestones)
        return DuplicateReport(tasks: taskGroups, milestones: milestoneGroups)
    }

    private func groupTasks(_ tasks: [TransitTask]) -> [DuplicateGroup] {
        var byId: [Int: [TransitTask]] = [:]
        for task in tasks {
            guard let displayId = task.permanentDisplayId else { continue }
            byId[displayId, default: []].append(task)
        }
        return byId
            .filter { $0.value.count >= 2 }
            .sorted { $0.key < $1.key }
            .map { displayId, members in
                let ordered = orderTasksWinnerFirst(members)
                let records = ordered.enumerated().map { index, task in
                    RecordRef(
                        id: task.id,
                        name: task.name,
                        projectName: task.project?.name ?? "(no project)",
                        creationDate: task.creationDate,
                        role: index == 0 ? .winner : .loser
                    )
                }
                return DuplicateGroup(displayId: displayId, records: records)
            }
    }

    private func groupMilestones(_ milestones: [Milestone]) -> [DuplicateGroup] {
        var byId: [Int: [Milestone]] = [:]
        for milestone in milestones {
            guard let displayId = milestone.permanentDisplayId else { continue }
            byId[displayId, default: []].append(milestone)
        }
        return byId
            .filter { $0.value.count >= 2 }
            .sorted { $0.key < $1.key }
            .map { displayId, members in
                let ordered = orderMilestonesWinnerFirst(members)
                let records = ordered.enumerated().map { index, milestone in
                    RecordRef(
                        id: milestone.id,
                        name: milestone.name,
                        projectName: milestone.project?.name ?? "(no project)",
                        creationDate: milestone.creationDate,
                        role: index == 0 ? .winner : .loser
                    )
                }
                return DuplicateGroup(displayId: displayId, records: records)
            }
    }

    private func orderTasksWinnerFirst(_ tasks: [TransitTask]) -> [TransitTask] {
        tasks.sorted { lhs, rhs in
            if lhs.creationDate != rhs.creationDate {
                return lhs.creationDate < rhs.creationDate
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func orderMilestonesWinnerFirst(_ milestones: [Milestone]) -> [Milestone] {
        milestones.sorted { lhs, rhs in
            if lhs.creationDate != rhs.creationDate {
                return lhs.creationDate < rhs.creationDate
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // MARK: - Reassign

    /// Reassigns fresh display IDs to losers in each duplicate group. Best-effort
    /// per-group; never throws. Concurrent calls return `.busy` immediately.
    func reassignDuplicates() async -> ReassignmentResult {
        guard !isReassigning else { return .busy }
        isReassigning = true
        defer { isReassigning = false }

        // One pair of fetches feeds both the duplicate report and the per-type
        // sampled max used for the counter-advance fence. A fetch failure surfaces
        // as a counter-advance warning rather than silently no-oping the run.
        let tasks: [TransitTask]
        let milestones: [Milestone]
        do {
            tasks = try modelContext.fetch(FetchDescriptor<TransitTask>())
            milestones = try modelContext.fetch(FetchDescriptor<Milestone>())
        } catch {
            let warning = "Fetch failed: \(error.localizedDescription)"
            return ReassignmentResult(
                status: .ok, groups: [],
                counterAdvance: CounterAdvanceResult(
                    task: CounterAdvanceEntry(advancedTo: nil, warning: warning),
                    milestone: CounterAdvanceEntry(advancedTo: nil, warning: warning)
                )
            )
        }

        let report = DuplicateReport(
            tasks: groupTasks(tasks),
            milestones: groupMilestones(milestones)
        )
        let taskMax = tasks.compactMap(\.permanentDisplayId).max()
        let milestoneMax = milestones.compactMap(\.permanentDisplayId).max()

        // Counter advance per type, independent. A failure aborts that type only.
        let taskAdvance = await advanceCounterIfNeeded(
            allocator: taskAllocator, sampledMax: taskMax
        )
        let milestoneAdvance = await advanceCounterIfNeeded(
            allocator: milestoneAllocator, sampledMax: milestoneMax
        )

        var groupResults: [GroupResult] = []
        for group in report.tasks {
            groupResults.append(await processTaskGroup(
                group, advanceWarning: taskAdvance?.warning
            ))
        }
        for group in report.milestones {
            groupResults.append(await processMilestoneGroup(
                group, advanceWarning: milestoneAdvance?.warning
            ))
        }

        return ReassignmentResult(
            status: .ok,
            groups: groupResults,
            counterAdvance: CounterAdvanceResult(task: taskAdvance, milestone: milestoneAdvance)
        )
    }

    private func processTaskGroup(_ group: DuplicateGroup, advanceWarning: String?) async -> GroupResult {
        // `count >= 2` is a `groupTasks`/`groupMilestones` invariant, so the
        // winner is always present.
        guard let winnerRef = group.records.first else { preconditionFailure("Empty duplicate group") }
        let winner = GroupResultWinner(id: winnerRef.id, name: winnerRef.name)
        let losers = Array(group.records.dropFirst())
        if let warning = advanceWarning {
            return GroupResult(
                type: .task, displayId: group.displayId,
                winner: winner, reassignments: [],
                failure: GroupFailure(code: .counterAdvanceFailed, message: warning)
            )
        }
        return await reassignTaskGroup(displayId: group.displayId, winner: winner, losers: losers)
    }

    private func processMilestoneGroup(_ group: DuplicateGroup, advanceWarning: String?) async -> GroupResult {
        guard let winnerRef = group.records.first else { preconditionFailure("Empty duplicate group") }
        let winner = GroupResultWinner(id: winnerRef.id, name: winnerRef.name)
        let losers = Array(group.records.dropFirst())
        if let warning = advanceWarning {
            return GroupResult(
                type: .milestone, displayId: group.displayId,
                winner: winner, reassignments: [],
                failure: GroupFailure(code: .counterAdvanceFailed, message: warning)
            )
        }
        return await reassignMilestoneGroup(displayId: group.displayId, winner: winner, losers: losers)
    }

    /// Message surfaced per group when duplicate cleanup is attempted with iCloud Sync
    /// off. Reassignment needs a fresh ID from the CloudKit counter, which is off limits
    /// in that mode (T-1797), so the run reports rather than silently doing nothing.
    static let cloudSyncInactiveWarning = """
        iCloud Sync is off, so the display ID counter is unavailable. Turn iCloud Sync on, \
        quit and reopen Transit, then run maintenance again.
        """

    /// Advances the counter to `sampledMax + 1` if `sampledMax` is non-nil.
    /// Returns nil when there are no records of that type (no fence needed).
    private func advanceCounterIfNeeded(
        allocator: DisplayIDAllocator, sampledMax: Int?
    ) async -> CounterAdvanceEntry? {
        guard let sampledMax else { return nil }
        guard allocator.isCloudSyncActive else {
            return CounterAdvanceEntry(advancedTo: nil, warning: Self.cloudSyncInactiveWarning)
        }
        let store = allocator.counterStore
        let target = sampledMax + 1
        do {
            try await store.advanceCounter(toAtLeast: target)
            let snapshot = try await store.loadCounter()
            return CounterAdvanceEntry(advancedTo: snapshot.nextDisplayID, warning: nil)
        } catch {
            return CounterAdvanceEntry(advancedTo: nil, warning: error.localizedDescription)
        }
    }

    private func reassignTaskGroup(
        displayId: Int, winner: GroupResultWinner, losers: [RecordRef]
    ) async -> GroupResult {
        var entries: [ReassignmentEntry] = []
        var failure: GroupFailure?

        for loser in losers {
            let outcome = await reassignTaskLoser(loser: loser, displayId: displayId)
            switch outcome {
            case .reassigned(let entry):
                entries.append(entry)
            case .failed(let groupFailure):
                failure = groupFailure
            }
            if failure != nil { break }
        }

        return GroupResult(
            type: .task, displayId: displayId,
            winner: winner, reassignments: entries, failure: failure
        )
    }

    private enum LoserOutcome {
        case reassigned(ReassignmentEntry)
        case failed(GroupFailure)
    }

    private func reassignTaskLoser(loser: RecordRef, displayId: Int) async -> LoserOutcome {
        guard let loserTask = lookup.task(id: loser.id) else {
            return .failed(GroupFailure(code: .staleId, message: "Task not found"))
        }
        guard let storedId = lookup.storedTaskDisplayId(id: loser.id) else {
            return .failed(GroupFailure(code: .staleId, message: "Display ID changed since scan"))
        }
        if storedId != displayId {
            return .failed(GroupFailure(code: .staleId, message: "Display ID changed since scan"))
        }
        let newId: Int
        do {
            // Exclude every committed ID, not just the duplicate being repaired: the
            // counter-advance fence above can be undone by a stale counter read, and
            // handing back an in-use ID would trade one collision for another (T-1766).
            newId = try await taskAllocator.allocateNextID(excluding: { try self.usedDisplayIDs.tasks() })
        } catch {
            return .failed(GroupFailure(code: .allocationFailed, message: error.localizedDescription))
        }
        // Allocation suspends, so the committed-ID probe above can expire while
        // waiting. Re-probe after the final await and adjacent to the write; a
        // skipped counter value is safer than overwriting a peer repair (T-2019).
        guard lookup.storedTaskDisplayId(id: loser.id) == displayId else {
            return .failed(GroupFailure(code: .staleId, message: "Display ID changed since scan"))
        }
        loserTask.permanentDisplayId = newId
        do {
            try modelContext.saveOrRollback()
        } catch {
            return .failed(GroupFailure(code: .saveFailed, message: error.localizedDescription))
        }
        let commentWarning = appendAuditComment(to: loserTask, oldId: displayId, newId: newId)
        return .reassigned(ReassignmentEntry(
            id: loser.id, name: loserTask.name,
            previousDisplayId: displayId, newDisplayId: newId,
            commentWarning: commentWarning
        ))
    }

    private func appendAuditComment(to task: TransitTask, oldId: Int, newId: Int) -> String? {
        let date = formattedToday()
        let auditText = "Display ID changed from T-\(oldId) to T-\(newId) during duplicate cleanup on \(date)."
        do {
            try commentService.addComment(
                to: task, content: auditText,
                authorName: "Transit Maintenance", isAgent: true,
                save: { try $0.save() }
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func reassignMilestoneGroup(
        displayId: Int, winner: GroupResultWinner, losers: [RecordRef]
    ) async -> GroupResult {
        var entries: [ReassignmentEntry] = []
        var failure: GroupFailure?

        for loser in losers {
            // Re-fetch to pick up any peer-merged changes since the scan.
            guard let loserMilestone = lookup.milestone(id: loser.id) else {
                failure = GroupFailure(code: .staleId, message: "Milestone not found")
                break
            }
            guard let storedId = lookup.storedMilestoneDisplayId(id: loser.id) else {
                failure = GroupFailure(code: .staleId, message: "Display ID changed since scan")
                break
            }
            if storedId != displayId {
                failure = GroupFailure(code: .staleId, message: "Display ID changed since scan")
                break
            }

            let newId: Int
            do {
                // See `reassignTaskLoser` (T-1766).
                newId = try await milestoneAllocator
                    .allocateNextID(excluding: { try self.usedDisplayIDs.milestones() })
            } catch {
                failure = GroupFailure(code: .allocationFailed, message: error.localizedDescription)
                break
            }

            // `allocateNextID` is the final suspension point. Validate the
            // committed loser again before mutating the scan-time object (T-2019).
            guard lookup.storedMilestoneDisplayId(id: loser.id) == displayId else {
                failure = GroupFailure(code: .staleId, message: "Display ID changed since scan")
                break
            }
            let previousId = displayId
            loserMilestone.permanentDisplayId = newId
            do {
                try modelContext.saveOrRollback()
            } catch {
                failure = GroupFailure(code: .saveFailed, message: error.localizedDescription)
                break
            }

            entries.append(ReassignmentEntry(
                id: loser.id, name: loserMilestone.name,
                previousDisplayId: previousId, newDisplayId: newId,
                commentWarning: nil
            ))
        }

        return GroupResult(
            type: .milestone, displayId: displayId,
            winner: winner, reassignments: entries, failure: failure
        )
    }

    private func formattedToday() -> String {
        Self.dateFormatter.string(from: clock())
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}
