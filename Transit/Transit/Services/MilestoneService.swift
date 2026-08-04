import Foundation
import SwiftData

/// Coordinates milestone creation, status changes, task assignment, and lookups.
/// Uses DisplayIDAllocator for display ID assignment with a separate counter
/// from tasks.
@MainActor @Observable
final class MilestoneService {

    private let modelContext: ModelContext
    private let displayIDAllocator: DisplayIDAllocator

    /// Injected store reads for direct lookup and collision checks.
    private let fetcher: any ModelFetching
    private let usedDisplayIDs: UsedDisplayIDs
    private let mutationSave: (ModelContext) throws -> Void

    /// Single-flight guard for `promoteProvisionalMilestones`. Prevents
    /// concurrent promotion runs from overlapping (T-597).
    private var isPromotingMilestones = false

    init(
        modelContext: ModelContext,
        displayIDAllocator: DisplayIDAllocator,
        fetcher: (any ModelFetching)? = nil,
        mutationSave: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.displayIDAllocator = displayIDAllocator
        self.fetcher = fetcher ?? modelContext
        self.usedDisplayIDs = UsedDisplayIDs(modelContext: modelContext, liveFetcher: self.fetcher)
        self.mutationSave = mutationSave
    }

    // MARK: - CRUD

    @discardableResult
    func createMilestone(
        name: String,
        description: String?,
        project: Project,
        save: ((ModelContext) throws -> Void)? = nil
    ) async throws -> Milestone {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw Error.invalidName
        }

        guard try !milestoneNameExists(trimmedName, in: project) else {
            throw Error.duplicateName
        }

        let displayID: DisplayID
        do {
            // Snapshot display IDs already committed locally inside the
            // allocation gate (via closure) so a stale counter read cannot
            // produce a duplicate milestone ID, even with a concurrent create
            // that committed just before us (T-1395).
            let id = try await displayIDAllocator.allocateNextID(excluding: { try self.usedDisplayIDs.milestones() })
            displayID = .permanent(id)
        } catch let error as CancellationError {
            // The allocation gate propagates CancellationError when this caller is
            // cancelled while waiting for an ID (T-1395). Cancellation must abort the
            // create before any insert/save so a cancelled request never mutates
            // persistent state — only genuine CloudKit/offline failures fall back to
            // a provisional ID (T-1426).
            throw error
        } catch DisplayIDAllocator.Error.usedIDLookupFailed(let description) {
            // The local store could not be read, so the collision guard never ran.
            // That is not the offline condition provisional IDs exist for, and a
            // provisional ID would hide a broken store behind a normal-looking
            // create — surface it instead (T-1621).
            throw DisplayIDAllocator.Error.usedIDLookupFailed(description: description)
        } catch {
            displayID = .provisional
        }

        // Counter stores are not required to cooperate with Swift cancellation.
        // Re-check after allocation handling and before any post-await model work
        // so a successfully allocated ID cannot turn a cancelled operation into a
        // persisted milestone (T-1765).
        try Task.checkCancellation()

        // Re-check uniqueness after the allocation await. The check above ran
        // before this method suspended, so a concurrent create could have
        // committed the same name in the meantime (T-1764). CloudKit-backed
        // SwiftData cannot express `@Attribute(.unique)`, so this service check
        // *is* the invariant — and it only holds if the last check and the insert
        // are not separated by a suspension point, which is the case from here on.
        guard try !milestoneNameExists(trimmedName, in: project) else {
            throw Error.duplicateName
        }

        let milestone = Milestone(
            name: trimmedName,
            description: description,
            project: project,
            displayID: displayID
        )

        try modelContext.insertOrDelete(milestone, save: save ?? mutationSave)
        return milestone
    }

    func updateMilestone(
        _ milestone: Milestone,
        name: String?,
        description: String?,
        clearDescription: Bool = false
    ) throws {
        if let name {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw Error.invalidName
            }

            if let project = milestone.project {
                guard try !milestoneNameExists(trimmedName, in: project, excluding: milestone.id) else {
                    throw Error.duplicateName
                }
            }

            milestone.name = trimmedName
        }

        if let description {
            milestone.milestoneDescription = description
        } else if clearDescription {
            milestone.milestoneDescription = nil
        }

        try modelContext.saveOrRollback(save: mutationSave)
    }

    func updateStatus(_ milestone: Milestone, to newStatus: MilestoneStatus) throws {
        // T-923: Same-status updates are no-ops for status side effects so retries and
        // idempotent automations don't spuriously rewrite completion timestamps and
        // pull old terminal milestones back into the current report window.
        guard milestone.statusRawValue != newStatus.rawValue else { return }

        milestone.statusRawValue = newStatus.rawValue
        milestone.lastStatusChangeDate = Date.now

        if newStatus.isTerminal {
            milestone.completionDate = Date.now
        } else {
            milestone.completionDate = nil
        }

        try modelContext.saveOrRollback(save: mutationSave)
    }

    func deleteMilestone(_ milestone: Milestone) throws {
        modelContext.delete(milestone)
        try modelContext.saveOrRollback(save: mutationSave)
    }

    // MARK: - Assignment

    /// Central validation point for milestone assignment (Decision 8).
    /// Validates that the task has a project and that the milestone belongs
    /// to the same project. Pass nil to unassign. Saves the model context.
    func setMilestone(_ milestone: Milestone?, on task: TransitTask, save: Bool = true) throws {
        if let milestone {
            guard task.project != nil else {
                throw Error.projectRequired
            }

            guard milestone.project?.id == task.project?.id else {
                throw Error.projectMismatch
            }
        }

        task.milestone = milestone

        if save { try modelContext.saveOrRollback(save: mutationSave) }
    }

    // MARK: - Promotion

    /// Finds milestones with provisional display IDs, allocates permanent IDs.
    /// Called from ConnectivityMonitor.onRestore and ScenePhaseModifier.
    /// `save` is injectable for tests that need to simulate a save failure
    /// after the permanent ID has been assigned in memory.
    func promoteProvisionalMilestones(
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) async {
        // Mirrors `DisplayIDAllocator.promoteProvisionalTasks`: with the live container
        // not CloudKit-backed there is nothing to promote to (T-1797).
        guard displayIDAllocator.isCloudSyncActive else { return }
        guard !isPromotingMilestones else { return }
        isPromotingMilestones = true
        defer { isPromotingMilestones = false }

        // CloudKit merges UUID-distinct records rather than enforcing the
        // project/name invariant. Repair duplicates imported since the last
        // lifecycle pass before doing display-ID maintenance (T-1938).
        do {
            try reconcileDuplicateNames()
        } catch {
            // A later launch/foreground/connectivity pass retries. Do not continue
            // with an unreadable or unsavable store and mask the maintenance failure.
            return
        }

        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.permanentDisplayId == nil },
            sortBy: [SortDescriptor(\.creationDate, order: .forward)]
        )

        guard let milestones = try? modelContext.fetch(descriptor), !milestones.isEmpty else {
            return
        }

        let recordLookup = DisplayIDRecordLookup(modelContext: modelContext)

        for milestone in milestones {
            let newID: Int
            do {
                // Recompute used IDs inside the gate so just-committed IDs are excluded (T-1395).
                newID = try await displayIDAllocator.allocateNextID(
                    excluding: { try self.usedDisplayIDs.milestones() }
                )
                // After suspension, transiently re-read committed state before
                // mutating the stale object; missing/unreadable records fail closed (T-2020).
                guard try recordLookup.milestoneIsStillProvisional(id: milestone.id) else {
                    // Leave a gap: the allocated value cannot be safely reused.
                    continue
                }
            } catch {
                // Stop; the next lifecycle pass retries remaining milestones.
                break
            }

            milestone.permanentDisplayId = newID
            do {
                try save(modelContext)
            } catch {
                // Reset only this run's value; preserve a peer merge.
                if milestone.permanentDisplayId == newID {
                    milestone.permanentDisplayId = nil
                }
                break
            }
        }
    }

    // MARK: - Lookup

    func findByID(_ id: UUID) throws -> Milestone {
        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.id == id }
        )
        guard let milestone = try fetcher.fetch(descriptor).first else {
            throw Error.milestoneNotFound
        }
        return milestone
    }

    func findByDisplayID(_ displayId: Int) throws -> Milestone {
        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.permanentDisplayId == displayId }
        )
        let milestones = try fetcher.fetch(descriptor)

        guard let first = milestones.first else {
            throw Error.milestoneNotFound
        }
        guard milestones.count == 1 else {
            throw Error.duplicateDisplayID
        }
        return first
    }

    /// Finds exactly one case-insensitive name match in a project.
    ///
    /// Duplicate names can arrive through CloudKit even though local creation is
    /// guarded. Never select `.first`: name-addressed callers must report the
    /// ambiguity and require a stable UUID/display ID until reconciliation runs.
    func findByName(_ name: String, in project: Project) throws -> Milestone? {
        let normalized = MilestoneNamePolicy.normalized(name)
        let projectID = project.id
        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.project?.id == projectID }
        )
        let matches = try fetcher.fetch(descriptor).filter {
            MilestoneNamePolicy.normalized($0.name) == normalized
        }
        guard let match = matches.first else { return nil }
        guard matches.count == 1 else { throw Error.ambiguousName }
        return match
    }

    // MARK: - Post-sync maintenance

    /// Restores project-scoped name uniqueness after CloudKit imports records
    /// independently created on different devices.
    ///
    /// The oldest record keeps its original name (UUID breaks timestamp ties).
    /// Every other record receives a deterministic UUID-derived suffix. Renaming,
    /// rather than deleting or merging, preserves descriptions, statuses, display
    /// IDs, and task assignments. The UUID also lets every device converge on the
    /// same names independently. Returns the number of records renamed.
    @discardableResult
    func reconcileDuplicateNames() throws -> Int {
        try MilestoneNameReconciler(modelContext: modelContext).reconcile()
    }

    func milestonesForProject(_ project: Project, status: MilestoneStatus? = nil) throws -> [Milestone] {
        let projectID = project.id
        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.project?.id == projectID }
        )
        var milestones = try fetcher.fetch(descriptor)
        if let status {
            let statusRaw = status.rawValue
            milestones = milestones.filter { $0.statusRawValue == statusRaw }
        }
        return milestones
    }

    /// Fetches all milestones from the model context.
    func fetchAllMilestones() throws -> [Milestone] {
        try modelContext.fetch(FetchDescriptor<Milestone>())
    }

    /// Fetches terminal (done/abandoned) milestones with project relationship prefetched.
    func fetchTerminalMilestones() throws -> [Milestone] {
        let predicate = #Predicate<Milestone> {
            $0.statusRawValue == "done" || $0.statusRawValue == "abandoned"
        }
        var descriptor = FetchDescriptor<Milestone>(predicate: predicate)
        descriptor.relationshipKeyPathsForPrefetching = [\.project]
        return try modelContext.fetch(descriptor)
    }

    /// Saves the model context. Rolls back on failure.
    func save() throws {
        try modelContext.saveOrRollback(save: mutationSave)
    }

    /// Whether the project already holds a milestone with this name
    /// (case-insensitive), optionally ignoring one milestone for renames.
    ///
    /// Throws the underlying storage error when the project's milestones cannot be
    /// read. CloudKit-backed SwiftData forbids `@Attribute(.unique)`, so this check
    /// *is* the uniqueness invariant — including the post-allocation re-check in
    /// `createMilestone` that closes the TOCTOU window (T-1764). Reporting `false`
    /// for an unreadable store would let both checks pass on a name that is already
    /// taken (T-1614).
    func milestoneNameExists(
        _ name: String, in project: Project, excluding milestoneId: UUID? = nil
    ) throws -> Bool {
        let normalized = MilestoneNamePolicy.normalized(name)
        let projectID = project.id
        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.project?.id == projectID }
        )
        let milestones = try fetcher.fetch(descriptor)
        return milestones.contains { milestone in
            if let milestoneId, milestone.id == milestoneId { return false }
            return MilestoneNamePolicy.normalized(milestone.name) == normalized
        }
    }

}

// MARK: - Errors

extension MilestoneService {

    enum Error: Swift.Error, Equatable, LocalizedError {
        case invalidName
        case milestoneNotFound
        case duplicateName
        case ambiguousName
        case duplicateDisplayID
        case projectRequired
        case projectMismatch

        var errorDescription: String? {
            switch self {
            case .invalidName:
                "Milestone name cannot be empty."
            case .milestoneNotFound:
                "The specified milestone could not be found."
            case .duplicateName:
                "A milestone with this name already exists in the project."
            case .ambiguousName:
                "Multiple milestones with this name exist in the project."
            case .duplicateDisplayID:
                "A duplicate milestone identifier was detected."
            case .projectRequired:
                "Task must belong to a project before assigning a milestone."
            case .projectMismatch:
                "Milestone and task must belong to the same project."
            }
        }
    }
}
