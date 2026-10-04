#if os(macOS)
import Foundation
@testable import Transit

/// Mutations of a real saved capture keep its physical keys and authoritative revisions.
/// Only the field being exercised changes; this is not a second capture provider.
nonisolated enum PortfolioSummaryTestValues {
    static let statuses = [
        "idea", "planning", "spec", "ready-for-implementation", "in-progress",
        "ready-for-review", "done", "abandoned"
    ]

    static func view(
        _ source: CapturedReadView, scope: ReadCaptureScope? = nil,
        projects: [ReadProject]? = nil, tasks: [ReadTask]? = nil,
        milestones: [ReadMilestone]? = nil, comments: [ReadCommentEvidence]? = nil,
        completeness: CaptureCompleteness? = nil
    ) -> CapturedReadView {
        CapturedReadView(
            completeness: completeness ?? source.completeness, captureScope: scope ?? source.captureScope,
            metadata: source.metadata, createdAt: source.createdAt,
            retentionDeadline: source.retentionDeadline,
            projects: projects ?? source.projects, tasks: tasks ?? source.tasks,
            milestones: milestones ?? source.milestones, comments: comments ?? source.comments
        )
    }

    static func project(_ source: ReadProject, id: UUID? = nil, name: String? = nil) -> ReadProject {
        ReadProject(
            physicalKey: source.physicalKey, id: id ?? source.id, name: name ?? source.name,
            projectDescription: source.projectDescription, gitRepo: source.gitRepo,
            colorHex: source.colorHex, taskKeys: source.taskKeys, milestoneKeys: source.milestoneKeys,
            selectedRecordJSON: source.selectedRecordJSON)
    }

    static func task(
        _ source: ReadTask, id: UUID? = nil, displayID: Int?? = nil, status: String? = nil,
        projectKey: LocalRecordKey?? = nil, milestoneKey: LocalRecordKey?? = nil,
        creation: Date? = nil, statusChange: Date? = nil, completion: Date?? = nil
    ) -> ReadTask {
        let raw = status ?? source.rawStatus
        return ReadTask(
            physicalKey: source.physicalKey, id: id ?? source.id,
            permanentDisplayId: displayID ?? source.permanentDisplayId, name: source.name,
            taskDescription: source.taskDescription, projectKey: projectKey ?? source.projectKey,
            milestoneKey: milestoneKey ?? source.milestoneKey, storedProjectID: source.storedProjectID,
            storedMilestoneID: source.storedMilestoneID, rawStatus: raw,
            effectiveStatus: statuses.contains(raw) ? raw : "idea", rawType: source.rawType,
            effectiveType: source.effectiveType, rawPriority: source.rawPriority,
            effectivePriority: source.effectivePriority, metadata: source.metadata,
            metadataJSON: source.metadataJSON, creationDate: creation ?? source.creationDate,
            lastStatusChangeDate: statusChange ?? source.lastStatusChangeDate,
            completionDate: completion ?? source.completionDate, commentKeys: source.commentKeys,
            selectedRecordJSON: source.selectedRecordJSON, revision: source.revision,
            fullRecordWithoutCommentsJSON: source.fullRecordWithoutCommentsJSON,
            requestedCommentRecordsJSON: source.requestedCommentRecordsJSON
        )
    }

    static func milestone(
        _ source: ReadMilestone, id: UUID? = nil, displayID: Int?? = nil, status: String? = nil,
        projectKey: LocalRecordKey?? = nil, creation: Date? = nil, statusChange: Date? = nil
    ) -> ReadMilestone {
        let raw = status ?? source.rawStatus
        return ReadMilestone(
            physicalKey: source.physicalKey, id: id ?? source.id,
            permanentDisplayId: displayID ?? source.permanentDisplayId, name: source.name,
            milestoneDescription: source.milestoneDescription,
            projectKey: projectKey ?? source.projectKey,
            storedProjectID: source.storedProjectID, rawStatus: raw,
            effectiveStatus: ["open", "done", "abandoned"].contains(raw) ? raw : "open",
            creationDate: creation ?? source.creationDate,
            lastStatusChangeDate: statusChange ?? source.lastStatusChangeDate,
            completionDate: source.completionDate, taskKeys: source.taskKeys,
            selectedRecordJSON: source.selectedRecordJSON
        )
    }

    static func comment(_ source: ReadCommentEvidence, creation: Date, taskKey: LocalRecordKey?? = nil)
        -> ReadCommentEvidence {
        ReadCommentEvidence(
            physicalKey: source.physicalKey, id: source.id,
            taskKey: taskKey ?? source.taskKey, storedTaskID: source.storedTaskID,
            creationDate: creation, content: source.content, authorName: source.authorName,
            isAgent: source.isAgent, selectedRecordJSON: source.selectedRecordJSON)
    }

    static func buckets(_ counts: PortfolioStatusCounts) -> [Int] {
        [
            counts.idea, counts.planning, counts.spec, counts.readyForImplementation,
            counts.inProgress, counts.readyForReview, counts.done, counts.abandoned
        ]
    }

    /// Reference filters deliberately do not use effectiveStatus or service helpers.
    static func referenceBuckets(_ tasks: [ReadTask]) -> [Int] {
        statuses.map { status in
            tasks.filter { statuses.contains($0.rawStatus) ? $0.rawStatus == status : status == "idea" }
                .count
        }
    }

    static func referenceCompletions(_ tasks: [ReadTask], window: CompletionWindow)
        -> PortfolioRecentCompletions {
        let inside: (ReadTask) -> Bool = { task in
            guard let date = task.completionDate else { return false }
            return date >= window.start && date < window.end
        }
        return PortfolioRecentCompletions(
            done: tasks.filter { $0.rawStatus == "done" && inside($0) }.count,
            abandoned: tasks.filter { $0.rawStatus == "abandoned" && inside($0) }.count,
            missingCompletionDateCount: tasks.filter {
                ["done", "abandoned"].contains($0.rawStatus) && $0.completionDate == nil
            }.count
        )
    }
}

/// Fixed seed and explicit Fisher–Yates make failing generated inputs reproducible.
nonisolated struct PortfolioSummarySeed {
    var state: UInt64
    mutating func next(_ upperBound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 32) % UInt64(upperBound))
    }
    mutating func shuffled<Value>(_ values: [Value]) -> [Value] {
        var result = values
        guard result.count > 1 else { return result }
        for index in stride(from: result.count - 1, through: 1, by: -1) {
            result.swapAt(index, next(index + 1))
        }
        return result
    }
}
#endif
