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
}
