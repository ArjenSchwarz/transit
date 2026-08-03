import Foundation
import SwiftData

/// Validates a task-creation milestone from both state sources that can be
/// current: the live context preserves pending local updates, while a fresh
/// context observes a peer's committed update even when the live model is
/// clean but stale. Every observed record must still be open and scoped to
/// `projectID`; a fetch error fails closed before task insertion. [T-2037]
enum TaskCreationMilestoneValidator {
    static func validate(
        _ milestone: Milestone?,
        projectID: UUID,
        in modelContext: ModelContext
    ) throws {
        guard let milestone else { return }

        let milestoneID = milestone.id
        let descriptor = FetchDescriptor<Milestone>(
            predicate: #Predicate { $0.id == milestoneID }
        )
        let liveMilestone = try modelContext.fetch(descriptor).first
        let committedMilestone = try ModelContext(modelContext.container).fetch(descriptor).first
        let currentMilestones = [liveMilestone, committedMilestone].compactMap { $0 }

        guard !currentMilestones.isEmpty else {
            throw TaskService.Error.milestoneNotOpen
        }
        for currentMilestone in currentMilestones {
            guard currentMilestone.project?.id == projectID else {
                throw TaskService.Error.milestoneProjectMismatch
            }
            guard currentMilestone.status == .open else {
                throw TaskService.Error.milestoneNotOpen
            }
        }
    }
}
