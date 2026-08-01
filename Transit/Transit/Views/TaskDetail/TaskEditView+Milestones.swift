import Foundation

extension TaskEditView {

    /// Milestones the picker may offer for `project`.
    ///
    /// Open milestones plus, when it belongs to the same project, whichever
    /// milestone is currently selected — otherwise assigning a task to a closed
    /// milestone would make the picker show a blank selection and silently drop
    /// the assignment on save.
    static func availableMilestones(
        project: Project?,
        selectedMilestone: Milestone?,
        milestoneService: MilestoneService
    ) -> [Milestone] {
        guard let project else { return [] }
        var milestones = milestoneService.milestonesForProject(project, status: .open)

        guard let selectedMilestone, selectedMilestone.project?.id == project.id else {
            return milestones
        }

        if milestones.contains(where: { $0.id == selectedMilestone.id }) == false {
            milestones.append(selectedMilestone)
        }

        return milestones
    }

    /// The milestone a rebased draft should select, or `nil` when none fits.
    ///
    /// A rebase merges each field independently, so an external project move can
    /// land alongside a preserved milestone edit made against the *old* project.
    /// Decision 6 — moving project clears the milestone — settles that pairing:
    /// a milestone from another project is dropped rather than carried into a
    /// draft whose next save `MilestoneService.setMilestone` would reject as a
    /// project mismatch, leaving the editor unable to save at all.
    ///
    /// `candidates` are the only milestones a rebased ID can name: the user's
    /// current selection and the one now on the task.
    static func rebasedMilestone(
        milestoneID: UUID?,
        projectID: UUID?,
        candidates: [Milestone?]
    ) -> Milestone? {
        guard let milestoneID else { return nil }

        return candidates
            .compactMap { $0 }
            .first { $0.id == milestoneID && $0.project?.id == projectID }
    }
}
