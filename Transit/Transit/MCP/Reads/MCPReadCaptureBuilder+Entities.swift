#if os(macOS)
import Foundation
import SwiftData

extension MCPReadCaptureBuilder {
    func milestoneIdentity(_ milestone: Milestone) -> ReadMilestoneIdentity {
        ReadMilestoneIdentity(id: milestone.id, permanentDisplayId: milestone.permanentDisplayId, name: milestone.name,
            storedProjectID: milestone.project?.id, rawStatus: milestone.statusRawValue,
            milestoneDescription: milestone.milestoneDescription)
    }

    func fetchEntities(_ request: ReadCaptureRequest, in context: ModelContext)
        throws -> ReadCaptureFetchedEntities {
        let (needsTasks, needsMilestones) = request.selection.requiredEntities
        let (allMilestones, needsTaskValues) = try request.measureCapture(.captureMilestones) {
            let milestones = needsMilestones ? try fetchMilestones(context) : []
            let needsValues = try request.validateMilestones?(milestones.map { milestoneIdentity($0) }) ?? needsTasks
            return (milestones, needsValues)
        }
        let allTasks = needsTasks && needsTaskValues
            ? try request.measureCapture(.captureTasks) { try fetchTasks(context) } : []
        return ReadCaptureFetchedEntities(tasks: allTasks, milestones: allMilestones,
                                          tasksCaptured: needsTasks && needsTaskValues)
    }
}
#endif
