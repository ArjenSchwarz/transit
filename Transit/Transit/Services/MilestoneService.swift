import Foundation
import SwiftData

/// Coordinates milestone creation, status changes, task assignment, and lookups.
/// Uses DisplayIDAllocator for display ID assignment with a separate counter
/// from tasks.
@MainActor @Observable
final class MilestoneService {

    enum Error: Swift.Error, Equatable, LocalizedError {
        case invalidName
        case milestoneNotFound
        case duplicateName
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
            case .projectRequired:
                "Task must belong to a project before assigning a milestone."
            case .projectMismatch:
                "Milestone and task must belong to the same project."
            }
        }
    }

    private let modelContext: ModelContext
    private let displayIDAllocator: DisplayIDAllocator

    init(modelContext: ModelContext, displayIDAllocator: DisplayIDAllocator) {
        self.modelContext = modelContext
        self.displayIDAllocator = displayIDAllocator
    }

    // MARK: - CRUD

    @discardableResult
    func createMilestone(
        name: String,
        description: String?,
        project: Project
    ) async throws -> Milestone {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw Error.invalidName
        }

        guard !milestoneNameExists(trimmedName, in: project) else {
            throw Error.duplicateName
        }

        let displayID: DisplayID
        do {
            let id = try await displayIDAllocator.allocateNextID()
            displayID = .permanent(id)
        } catch {
            displayID = .provisional
        }

        let milestone = Milestone(
            name: trimmedName,
            description: description,
            project: project,
            displayID: displayID
        )

        modelContext.insert(milestone)
        try modelContext.save()
        return milestone
    }

    func updateMilestone(
        _ milestone: Milestone,
        name: String?,
        description: String?
    ) throws {
        if let name {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty else {
                throw Error.invalidName
            }

            if let project = milestone.project {
                guard !milestoneNameExists(trimmedName, in: project, excluding: milestone.id) else {
                    throw Error.duplicateName
                }
            }

            milestone.name = trimmedName
        }

        if let description {
            milestone.milestoneDescription = description
        }

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func updateStatus(_ milestone: Milestone, to newStatus: MilestoneStatus) throws {
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
            modelContext.rollback()
            throw error
        }
    }

    func deleteMilestone(_ milestone: Milestone) throws {
        modelContext.delete(milestone)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    // MARK: - Assignment

    /// Central validation point for milestone assignment (Decision 8).
    /// Validates that the task has a project and that the milestone belongs
    /// to the same project. Pass nil to unassign. Saves the model context.
    func setMilestone(_ milestone: Milestone?, on task: TransitTask) throws {
        if let milestone {
            guard task.project != nil else {
                throw Error.projectRequired
            }

            guard milestone.project?.id == task.project?.id else {
                throw Error.projectMismatch
            }
        }

        task.milestone = milestone

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    // MARK: - Promotion

    /// Finds milestones with provisional display IDs, allocates permanent IDs.
    /// Called from ConnectivityMonitor.onRestore and ScenePhaseModifier.
    func promoteProvisionalMilestones() async {
        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.permanentDisplayId == nil },
            sortBy: [SortDescriptor(\.creationDate, order: .forward)]
        )

        guard let milestones = try? modelContext.fetch(descriptor), !milestones.isEmpty else {
            return
        }

        for milestone in milestones {
            do {
                let newID = try await displayIDAllocator.allocateNextID()
                milestone.permanentDisplayId = newID
                try modelContext.save()
            } catch {
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
        guard let milestone = try modelContext.fetch(descriptor).first else {
            throw Error.milestoneNotFound
        }
        return milestone
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

    func milestoneNameExists(_ name: String, in project: Project, excluding milestoneId: UUID? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectID = project.id
        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.project?.id == projectID }
        )
        let milestones = (try? modelContext.fetch(descriptor)) ?? []
        return milestones.contains { milestone in
            if let milestoneId, milestone.id == milestoneId { return false }
            return milestone.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }
}
