import Foundation
import SwiftData

/// Coordinates milestone creation, status changes, task assignment, and lookups.
/// Uses DisplayIDAllocator for display ID assignment with a separate counter
/// from tasks.
@MainActor @Observable
final class MilestoneService {

    private let modelContext: ModelContext
    private let displayIDAllocator: DisplayIDAllocator

    /// Store reads for the two invariants that are derived from a fetch result —
    /// name uniqueness and the used-display-ID snapshot. Separate from
    /// `modelContext` only so tests can inject a failing fetch (T-1614, T-1621);
    /// production always passes the same context.
    private let fetcher: any ModelFetching
    private let usedDisplayIDs: UsedDisplayIDs

    /// Single-flight guard for `promoteProvisionalMilestones`. Prevents
    /// concurrent promotion runs from overlapping (T-597).
    private var isPromotingMilestones = false

    init(
        modelContext: ModelContext,
        displayIDAllocator: DisplayIDAllocator,
        fetcher: (any ModelFetching)? = nil
    ) {
        self.modelContext = modelContext
        self.displayIDAllocator = displayIDAllocator
        self.fetcher = fetcher ?? modelContext
        self.usedDisplayIDs = UsedDisplayIDs(fetcher ?? modelContext)
    }

    // MARK: - CRUD

    @discardableResult
    func createMilestone(
        name: String,
        description: String?,
        project: Project,
        save: (ModelContext) throws -> Void = { try $0.save() }
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

        modelContext.insert(milestone)
        do {
            try save(modelContext)
        } catch {
            modelContext.delete(milestone)
            throw error
        }
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

        do {
            try modelContext.save()
        } catch {
            modelContext.safeRollback()
            throw error
        }
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

        do {
            try modelContext.save()
        } catch {
            modelContext.safeRollback()
            throw error
        }
    }

    func deleteMilestone(_ milestone: Milestone) throws {
        modelContext.delete(milestone)
        do {
            try modelContext.save()
        } catch {
            modelContext.safeRollback()
            throw error
        }
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

        guard save else { return }

        do {
            try modelContext.save()
        } catch {
            modelContext.safeRollback()
            throw error
        }
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

        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.permanentDisplayId == nil },
            sortBy: [SortDescriptor(\.creationDate, order: .forward)]
        )

        guard let milestones = try? modelContext.fetch(descriptor), !milestones.isEmpty else {
            return
        }

        for milestone in milestones {
            do {
                // Recompute used IDs inside the gate so a promoted ID never
                // collides with one already committed (including ones just
                // assigned in this loop) (T-1395).
                let newID = try await displayIDAllocator.allocateNextID(
                    excluding: { try self.usedDisplayIDs.milestones() }
                )
                milestone.permanentDisplayId = newID
                try save(modelContext)
            } catch {
                // Revert only this promotion attempt so unrelated unsaved edits
                // on the shared context survive connectivity-triggered retries.
                milestone.permanentDisplayId = nil
                // Stop on first failure -- remaining milestones will be retried next pass.
                break
            }
        }
    }

    // MARK: - Lookup

    func findByID(_ id: UUID) throws -> Milestone {
        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.id == id }
        )
        guard let milestone = try modelContext.fetch(descriptor).first else {
            throw Error.milestoneNotFound
        }
        return milestone
    }

    func findByDisplayID(_ displayId: Int) throws -> Milestone {
        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.permanentDisplayId == displayId }
        )
        let milestones = try modelContext.fetch(descriptor)

        guard let first = milestones.first else {
            throw Error.milestoneNotFound
        }
        guard milestones.count == 1 else {
            throw Error.duplicateDisplayID
        }
        return first
    }

    func findByName(_ name: String, in project: Project) -> Milestone? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectID = project.id
        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.project?.id == projectID }
        )
        let milestones = (try? modelContext.fetch(descriptor)) ?? []
        return milestones.first {
            $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    func milestonesForProject(_ project: Project, status: MilestoneStatus? = nil) -> [Milestone] {
        let projectID = project.id
        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.project?.id == projectID }
        )
        var milestones = (try? modelContext.fetch(descriptor)) ?? []
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
        do {
            try modelContext.save()
        } catch {
            modelContext.safeRollback()
            throw error
        }
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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectID = project.id
        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.project?.id == projectID }
        )
        let milestones = try fetcher.fetch(descriptor)
        return milestones.contains { milestone in
            if let milestoneId, milestone.id == milestoneId { return false }
            return milestone.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }
}

// MARK: - Errors

extension MilestoneService {

    enum Error: Swift.Error, Equatable, LocalizedError {
        case invalidName
        case milestoneNotFound
        case duplicateName
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
