#if os(macOS)
import Foundation

extension MCPReadService {
    func captureRequest(tool: String, arguments: [String: Any], selection: ReadCaptureSelection,
                        includeComments: Bool, query: MCPTaskQueryRequest?) -> ReadCaptureRequest {
        let fields = arguments.mapValues(AnyCodable.init)
        let state = ValidationState()
        return ReadCaptureRequest(projectSelectors: nil, selection: selection,
                completeness: .selectedRead, includeComments: includeComments,
                validateProjects: { projects in
                    let args = fields.mapValues(\.value)
                    guard tool != "get_projects" else { return }
                    state.project = try MCPReadProjection.projectIdentity(args, projects: projects,
                                                             validateIgnoredName: tool == "query_tasks")
                    if tool == "query_tasks" {
                        try MCPReadProjection.validateTaskScalars(args)
                    } else {
                        try MCPReadProjection.enumeration(args, key: "status", type: MilestoneStatus.self)
                        try MCPReadProjection.string(args, key: "search")
                        try MCPReadProjection.integer(args, key: "displayId")
                    }
                }, validateMilestones: { milestones in
                    let args = fields.mapValues(\.value)
                    state.milestones = milestones
                    if tool == "query_tasks" {
                        if case .noMatch = try MCPReadProjection.milestoneFilter(args, project: state.project,
                                                                               milestones: milestones) { return false }
                        return true
                    }
                    guard tool == "query_milestones", let id = IntentHelpers.parseIntValue(args["displayId"]) else {
                        return tool == "get_projects"
                    }
                    let matches = milestones.filter { $0.permanentDisplayId == id }
                    guard matches.count <= 1 else {
                        throw MCPTaskQueryError(code: "AMBIGUOUS_FILTER",
                            message: "Duplicate milestone identifier detected for displayId \(id)")
                    }
                    guard let match = matches.first else { return false }
                    return MCPReadProjection.matchesMilestone(match, arguments: args, projectID: state.project?.id)
                }, selectTaskBodies: { values in
                    guard let query else { return Set(values.map(\.physicalKey)) }
                    let filters = try MCPReadProjection.taskFilters(fields.mapValues(\.value),
                        project: state.project, milestones: state.milestones)
                    return try MCPReadProjection.taskBodyKeys(values, request: query, filters: filters)
                }, selectMilestoneBodies: { values in
                    guard tool == "query_milestones" else { return [] }
                    return try MCPReadProjection.milestoneBodyKeys(values, arguments: fields.mapValues(\.value),
                        projectID: state.project?.id)
                })
    }

    private final class ValidationState {
        var project: ReadProjectIdentity?
        var milestones: [ReadMilestoneIdentity] = []
    }

}
#endif
