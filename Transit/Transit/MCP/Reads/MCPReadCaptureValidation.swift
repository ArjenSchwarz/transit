#if os(macOS)
import Foundation

/// Provider-side validation only. Public snapshot query/filter behavior belongs to T2382.
nonisolated enum MCPReadCaptureValidation {
    static func validateReusableCapture(_ view: CapturedReadView) throws {
        guard view.completeness == .completePortfolio else { throw MCPReadCaptureError.incoherentCapture }
        let projects = Set(view.projects.map(\.physicalKey))
        let tasks = Set(view.tasks.map(\.physicalKey))
        let milestones = Set(view.milestones.map(\.physicalKey))
        let comments = Set(view.comments.map(\.physicalKey))
        guard projects.count == view.projects.count, tasks.count == view.tasks.count,
              milestones.count == view.milestones.count, comments.count == view.comments.count else {
            throw MCPReadCaptureError.incoherentCapture
        }
        let scope: Set<LocalRecordKey>?
        switch view.captureScope {
        case .wholePortfolio: scope = nil
        case .projects(let keys):
            let selected = Set(keys)
            guard selected.count == keys.count, selected.isSubset(of: projects) else {
                throw MCPReadCaptureError.incoherentCapture
            }
            scope = selected
        case .selectedQuery: throw MCPReadCaptureError.incoherentCapture
        }
        try validateEndpoints(view, projects: projects, tasks: tasks, milestones: milestones)
        try validateTasks(view, projects: projects, milestones: milestones, scope: scope)
        for comment in view.comments {
            guard comment.taskKey.map({ tasks.contains($0) }) ?? true else {
                throw MCPReadCaptureError.incoherentCapture
            }
        }
    }

    private static func validateEndpoints(_ view: CapturedReadView, projects: Set<LocalRecordKey>,
                                          tasks: Set<LocalRecordKey>, milestones: Set<LocalRecordKey>) throws {
        for project in view.projects {
            guard Set(project.taskKeys).isSubset(of: tasks), Set(project.milestoneKeys).isSubset(of: milestones) else {
                throw MCPReadCaptureError.incoherentCapture
            }
        }
        for milestone in view.milestones {
            guard milestone.projectKey.map({ projects.contains($0) }) ?? true,
                  Set(milestone.taskKeys).isSubset(of: tasks) else { throw MCPReadCaptureError.incoherentCapture }
        }
    }

    private static func validateTasks(_ view: CapturedReadView, projects: Set<LocalRecordKey>,
                                      milestones: Set<LocalRecordKey>, scope: Set<LocalRecordKey>?) throws {
        let owners = Dictionary(grouping: view.comments.compactMap { comment in
            comment.taskKey.map { ($0, comment.physicalKey) }
        }, by: { $0.0 }).mapValues { Set($0.map(\.1)) }
        for task in view.tasks {
            guard task.projectKey.map({ projects.contains($0) }) ?? true,
                  task.milestoneKey.map({ milestones.contains($0) }) ?? true,
                  Set(task.commentKeys) == owners[task.physicalKey, default: []],
                  Set(task.commentKeys).count == task.commentKeys.count else {
                throw MCPReadCaptureError.incoherentCapture
            }
            let selected = scope.map { keys in task.projectKey.map { keys.contains($0) } == true } ?? true
            if selected { try validateCanonicalRecord(task) }
        }
    }

    /// A typed consumer scope check; public query parsing and selection remain with its owner.
    static func requireScope(_ view: CapturedReadView, projectKeys: Set<LocalRecordKey>) throws {
        let allowed: Set<LocalRecordKey>
        switch view.captureScope {
        case .wholePortfolio: allowed = Set(view.projects.map(\.physicalKey))
        case .projects(let keys): allowed = Set(keys)
        case .selectedQuery: throw MCPReadCaptureError.incoherentCapture
        }
        guard projectKeys.isSubset(of: allowed) else {
            throw MCPTaskQueryError(code: "SNAPSHOT_INCOMPATIBLE",
                                    message: "Requested projects are outside the retained capture scope")
        }
    }

    private static func validateCanonicalRecord(_ task: ReadTask) throws {
        guard let revision = task.revision, let bytes = task.fullRecordWithoutCommentsJSON else {
            throw MCPReadCaptureError.incoherentCapture
        }
        do {
            guard let record = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  record["revision"] as? String == revision,
                  record["taskId"] as? String == task.id.uuidString else {
                throw MCPReadCaptureError.incoherentCapture
            }
        } catch { throw MCPReadCaptureError.incoherentCapture }
    }
}
#endif
