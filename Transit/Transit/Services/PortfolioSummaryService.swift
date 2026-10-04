#if os(macOS)
import Foundation

/// Pure saved-value aggregation. Identity closure validates attribution but never expands scope.
nonisolated enum PortfolioSummaryService {
    private static let taskStatuses = [
        "idea", "planning", "spec", "ready-for-implementation", "in-progress",
        "ready-for-review", "done", "abandoned"
    ]

    static func summarize(view: CapturedReadView, window: CompletionWindow) throws -> PortfolioSummary {
        try Task.checkCancellation()
        guard view.completeness == .completePortfolio else { throw PortfolioSummaryError.incoherentCapture }
        guard window.start < window.end else { throw CompletionWindowError.invalidInput }
        let projectIndex = try index(view.projects, key: \.physicalKey)
        let taskIndex = try index(view.tasks, key: \.physicalKey)
        let milestoneIndex = try index(view.milestones, key: \.physicalKey)
        _ = try index(view.comments, key: \.physicalKey)
        let selectedKeys: Set<LocalRecordKey>
        switch view.captureScope {
        case .wholePortfolio: selectedKeys = Set(projectIndex.keys)
        case .projects(let keys):
            selectedKeys = Set(keys)
            guard !keys.isEmpty, selectedKeys.count == keys.count,
                  selectedKeys.allSatisfy({ projectIndex[$0] != nil }) else {
                throw PortfolioSummaryError.incoherentCapture
            }
        case .selectedQuery: throw PortfolioSummaryError.incoherentCapture
        }
        let wholePortfolio = view.captureScope == .wholePortfolio
        let tasks = view.tasks.filter { task in
            wholePortfolio || task.projectKey.map { selectedKeys.contains($0) } == true
        }
        let milestones = view.milestones.filter {
            $0.projectKey.map { selectedKeys.contains($0) } == true
        }
        try validateIdentities(view: view, projects: selectedKeys, tasks: tasks, milestones: milestones)
        let projects = selectedKeys.compactMap { projectIndex[$0] }.sorted(by: projectPrecedes)
        var state = Aggregation(
            builders: Dictionary(uniqueKeysWithValues: projects.map { ($0.physicalKey, ProjectBuilder()) }),
            milestoneCounts: Dictionary(uniqueKeysWithValues: milestones.map { ($0.physicalKey, TaskCounts()) }))
        try accumulateTasks(tasks, milestoneIndex: milestoneIndex, window: window, state: &state)
        try accumulateMilestones(milestones, builders: &state.builders)
        try accumulateComments(view.comments, taskIndex: taskIndex, builders: &state.builders)
        let milestonesByProject = Dictionary(grouping: milestones, by: \.projectKey)
        let summaries = projects.map { project in
            projectSummary(project, builder: state.builders[project.physicalKey]!,
                           milestones: milestonesByProject[project.physicalKey] ?? [],
                           milestoneCounts: state.milestoneCounts)
        }
        var diagnostics = collisionDiagnostics(
            view: view, projectKeys: selectedKeys, tasks: tasks, milestones: milestones)
        if !state.unresolvedSamples.isEmpty {
            diagnostics.append(diagnostic("unresolved_project", state.unresolvedSamples))
        }
        if !state.unresolvedInvalidStatuses.isEmpty {
            diagnostics.append(diagnostic("invalid_task_status", state.unresolvedInvalidStatuses))
        }
        return PortfolioSummary(
            projects: summaries, unresolvedProjects: state.unresolved.breakdown,
            diagnostics: diagnostics.sorted { $0.category < $1.category }, completionWindow: window)
    }
}

extension PortfolioSummaryService {
    nonisolated private static func accumulateTasks(
        _ tasks: [ReadTask], milestoneIndex: [LocalRecordKey: ReadMilestone], window: CompletionWindow,
        state: inout Aggregation
    ) throws {
        for (offset, task) in tasks.enumerated() {
            try checkpoint(offset)
            guard let projectKey = task.projectKey, state.builders[projectKey] != nil else {
                state.unresolved.add(task, window: window)
                state.unresolvedSamples.append(sample(task))
                if !taskStatuses.contains(task.rawStatus) { state.unresolvedInvalidStatuses.append(sample(task)) }
                continue
            }
            var builder = state.builders[projectKey]!
            builder.total.add(task, window: window)
            builder.activity.consider(task.creationDate, kind: .taskCreation, id: task.id, key: task.physicalKey)
            builder.activity.consider(task.lastStatusChangeDate, kind: .taskStatus, id: task.id, key: task.physicalKey)
            if !taskStatuses.contains(task.rawStatus) { builder.invalidStatuses.append(sample(task)) }
            if let key = task.milestoneKey {
                if let milestone = milestoneIndex[key], milestone.projectKey == projectKey {
                    state.milestoneCounts[key, default: TaskCounts()].add(task, window: window)
                } else {
                    builder.invalidMilestones.add(task, window: window)
                    builder.invalidLinks.append(sample(task))
                }
            } else { builder.unassigned.add(task, window: window) }
            state.builders[projectKey] = builder
        }
    }

    nonisolated private static func accumulateMilestones(
        _ milestones: [ReadMilestone], builders: inout [LocalRecordKey: ProjectBuilder]
    ) throws {
        for (offset, milestone) in milestones.enumerated() {
            try checkpoint(offset)
            guard let key = milestone.projectKey else { continue }
            builders[key]?.activity.consider(
                milestone.creationDate, kind: .milestoneCreation, id: milestone.id, key: milestone.physicalKey)
            builders[key]?.activity.consider(
                milestone.lastStatusChangeDate, kind: .milestoneStatus, id: milestone.id, key: milestone.physicalKey)
            if !["open", "done", "abandoned"].contains(milestone.rawStatus) {
                builders[key]?.invalidMilestoneStatuses.append(sample(milestone))
            }
        }
    }

    nonisolated private static func accumulateComments(
        _ comments: [ReadCommentEvidence], taskIndex: [LocalRecordKey: ReadTask],
        builders: inout [LocalRecordKey: ProjectBuilder]
    ) throws {
        for (offset, comment) in comments.enumerated() {
            try checkpoint(offset)
            guard let taskKey = comment.taskKey, let task = taskIndex[taskKey],
                  let projectKey = task.projectKey, builders[projectKey] != nil else { continue }
            builders[projectKey]?.activity.consider(
                comment.creationDate, kind: .commentCreation, id: comment.id, key: comment.physicalKey)
        }
    }

    nonisolated private static func checkpoint(_ offset: Int) throws {
        if offset.isMultiple(of: 256) { try Task.checkCancellation() }
    }

    nonisolated private static func index<Record>(_ records: [Record], key: KeyPath<Record, LocalRecordKey>) throws
        -> [LocalRecordKey: Record] {
        var result: [LocalRecordKey: Record] = [:]
        for (offset, record) in records.enumerated() {
            try checkpoint(offset)
            guard result.updateValue(record, forKey: record[keyPath: key]) == nil else {
                throw PortfolioSummaryError.incoherentCapture
            }
        }
        return result
    }

    nonisolated static func validateIdentities(
        view: CapturedReadView, projects: Set<LocalRecordKey>, tasks: [ReadTask], milestones: [ReadMilestone]
    ) throws {
        let selectedTaskKeys = Set(tasks.map(\.physicalKey))
        let relatedMilestoneKeys = Set(milestones.map(\.physicalKey)).union(tasks.compactMap(\.milestoneKey))
        let relatedProjectKeys = projects.union(view.milestones.filter {
            relatedMilestoneKeys.contains($0.physicalKey)
        }.compactMap(\.projectKey))
        try rejectDuplicateUUIDs(view.projects, id: \.id, key: \.physicalKey, relevant: relatedProjectKeys)
        try rejectDuplicateUUIDs(view.tasks, id: \.id, key: \.physicalKey, relevant: selectedTaskKeys)
        try rejectDuplicateUUIDs(view.milestones, id: \.id, key: \.physicalKey, relevant: relatedMilestoneKeys)
        let relevantComments = Set(view.comments.filter {
            $0.taskKey.map { selectedTaskKeys.contains($0) } == true
        }.map(\.physicalKey))
        try rejectDuplicateUUIDs(view.comments, id: \.id, key: \.physicalKey, relevant: relevantComments)
    }

    nonisolated private static func rejectDuplicateUUIDs<Record>(
        _ records: [Record], id: KeyPath<Record, UUID>, key: KeyPath<Record, LocalRecordKey>,
        relevant: Set<LocalRecordKey>
    ) throws {
        let groups = Dictionary(grouping: records) { $0[keyPath: id] }
        for group in groups.values where group.count > 1 {
            if group.contains(where: { relevant.contains($0[keyPath: key]) }) {
                throw PortfolioSummaryError.identityAmbiguity
            }
        }
    }

    nonisolated private static func projectSummary(
        _ project: ReadProject, builder: ProjectBuilder, milestones: [ReadMilestone],
        milestoneCounts: [LocalRecordKey: TaskCounts]
    ) -> PortfolioProjectSummary {
        let counts = builder.total.statuses
        let workflow = counts.planning + counts.spec + counts.readyForImplementation
            + counts.inProgress + counts.readyForReview
        let rows = milestones.sorted {
            ($0.id.uuidString, keyString($0.physicalKey)) < ($1.id.uuidString, keyString($1.physicalKey))
        }.map { milestone in
            let total = milestoneCounts[milestone.physicalKey] ?? TaskCounts()
            let validStatus = ["open", "done", "abandoned"].contains(milestone.rawStatus)
            return PortfolioMilestoneSummary(
                milestoneId: milestone.id, displayId: milestone.permanentDisplayId, name: milestone.name,
                rawStatus: milestone.rawStatus, status: validStatus ? milestone.rawStatus : "open",
                invalidStatus: !validStatus, countsByStatus: total.statuses,
                totalTaskCount: total.count, recentCompletions: total.recent)
        }
        let diagnostics = [
            ("invalid_task_status", builder.invalidStatuses),
            ("invalid_milestone_status", builder.invalidMilestoneStatuses),
            ("invalid_milestone_association", builder.invalidLinks)
        ].filter { !$0.1.isEmpty }.map { diagnostic($0.0, $0.1) }.sorted { $0.category < $1.category }
        return PortfolioProjectSummary(
            projectId: project.id, name: project.name, countsByStatus: counts, totalTaskCount: builder.total.count,
            ideaCount: counts.idea, inProgressCount: counts.inProgress, workflowTaskCount: workflow,
            nonterminalTaskCount: counts.idea + workflow, recentCompletions: builder.total.recent,
            lastRecordedActivity: builder.activity.evidence, milestones: rows,
            unassignedMilestone: builder.unassigned.breakdown,
            invalidMilestoneAssociations: builder.invalidMilestones.breakdown, diagnostics: diagnostics)
    }

    nonisolated private static func normalizedName(_ name: String) -> String {
        // Same POSIX folding as actor-isolated ProjectNamePolicy; no live name resolution.
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    nonisolated private static func projectPrecedes(_ lhs: ReadProject, _ rhs: ReadProject) -> Bool {
        (normalizedName(lhs.name), lhs.id.uuidString, keyString(lhs.physicalKey))
            < (normalizedName(rhs.name), rhs.id.uuidString, keyString(rhs.physicalKey))
    }

    nonisolated private static func collisionDiagnostics(
        view: CapturedReadView, projectKeys: Set<LocalRecordKey>, tasks: [ReadTask], milestones: [ReadMilestone]
    ) -> [PortfolioDiagnostic] {
        let taskKeys = Set(tasks.map(\.physicalKey))
        let milestoneKeys = Set(milestones.map(\.physicalKey)).union(tasks.compactMap(\.milestoneKey))
        let names = Dictionary(grouping: view.projects) { normalizedName($0.name) }.values.filter {
            $0.count > 1 && $0.contains { projectKeys.contains($0.physicalKey) }
        }.flatMap { $0.map(sample) }
        let taskIDs = Dictionary(grouping: view.tasks.filter { $0.permanentDisplayId != nil }) {
            $0.permanentDisplayId!
        }.values.filter { $0.count > 1 && $0.contains { taskKeys.contains($0.physicalKey) } }.flatMap { $0.map(sample) }
        let milestoneIDs = Dictionary(grouping: view.milestones.filter { $0.permanentDisplayId != nil }) {
            $0.permanentDisplayId!
        }.values.filter {
            $0.count > 1 && $0.contains { milestoneKeys.contains($0.physicalKey) }
        }.flatMap { $0.map(sample) }
        return [
            ("duplicate_project_name", names), ("duplicate_task_display_id", taskIDs),
            ("duplicate_milestone_display_id", milestoneIDs)
        ].filter { !$0.1.isEmpty }.map { diagnostic($0.0, $0.1) }
    }

    nonisolated private static func keyString(_ key: LocalRecordKey) -> String {
        key.encodedIdentifier.base64EncodedString()
    }
    nonisolated private static func sample(_ task: ReadTask) -> Sample {
        Sample(kind: "task", id: task.id, displayID: task.permanentDisplayId, key: task.physicalKey)
    }
    nonisolated private static func sample(_ milestone: ReadMilestone) -> Sample {
        Sample(kind: "milestone", id: milestone.id, displayID: milestone.permanentDisplayId, key: milestone.physicalKey)
    }
    nonisolated private static func sample(_ project: ReadProject) -> Sample {
        Sample(kind: "project", id: project.id, displayID: nil, key: project.physicalKey)
    }
    nonisolated private static func diagnostic(_ category: String, _ samples: [Sample]) -> PortfolioDiagnostic {
        let ordered = samples.sorted {
            if $0.kind != $1.kind { return $0.kind < $1.kind }
            if $0.id != $1.id { return $0.id.uuidString < $1.id.uuidString }
            if $0.displayID != $1.displayID { return ($0.displayID ?? Int.min) < ($1.displayID ?? Int.min) }
            return keyString($0.key) < keyString($1.key)
        }
        return PortfolioDiagnostic(
            category: category, affectedCount: samples.count,
            samples: ordered.prefix(10).map {
                PortfolioIdentitySample(entityKind: $0.kind, id: $0.id, displayId: $0.displayID,
                                        discriminator: keyString($0.key))
            }, sampleComplete: samples.count <= 10)
    }

}

extension PortfolioSummaryService {
    nonisolated private struct Aggregation {
        var builders: [LocalRecordKey: ProjectBuilder]
        var milestoneCounts: [LocalRecordKey: TaskCounts]
        var unresolved = TaskCounts()
        var unresolvedSamples: [Sample] = []
        var unresolvedInvalidStatuses: [Sample] = []
    }

    nonisolated private struct Sample {
        let kind: String
        let id: UUID
        let displayID: Int?
        let key: LocalRecordKey
    }

    nonisolated private struct ProjectBuilder {
        var total = TaskCounts()
        var unassigned = TaskCounts()
        var invalidMilestones = TaskCounts()
        var activity = Activity()
        var invalidStatuses: [Sample] = []
        var invalidMilestoneStatuses: [Sample] = []
        var invalidLinks: [Sample] = []
    }

    nonisolated private struct TaskCounts {
        var buckets = Array(repeating: 0, count: 8)
        var done = 0
        var abandoned = 0
        var missing = 0
        var count: Int { buckets.reduce(0, +) }
        var statuses: PortfolioStatusCounts {
            PortfolioStatusCounts(idea: buckets[0], planning: buckets[1], spec: buckets[2],
                                  readyForImplementation: buckets[3], inProgress: buckets[4],
                                  readyForReview: buckets[5], done: buckets[6], abandoned: buckets[7])
        }
        var recent: PortfolioRecentCompletions {
            PortfolioRecentCompletions(done: done, abandoned: abandoned, missingCompletionDateCount: missing)
        }
        var breakdown: PortfolioTaskBreakdown {
            PortfolioTaskBreakdown(countsByStatus: statuses, totalTaskCount: count, recentCompletions: recent)
        }
        mutating func add(_ task: ReadTask, window: CompletionWindow) {
            let bucket = taskStatuses.firstIndex(of: task.rawStatus) ?? 0
            buckets[bucket] += 1
            guard bucket >= 6 else { return }
            guard let date = task.completionDate else { missing += 1; return }
            guard window.start <= date, date < window.end else { return }
            if bucket == 6 { done += 1 } else { abandoned += 1 }
        }
    }

    nonisolated private struct Activity {
        var evidence: PortfolioActivityEvidence?
        var physicalKey: LocalRecordKey?
        mutating func consider(_ timestamp: Date, kind: PortfolioActivityKind, id: UUID, key: LocalRecordKey) {
            if let previous = evidence, let previousKey = physicalKey {
                guard timestamp > previous.timestamp || (timestamp == previous.timestamp
                    && (kind.rawValue, id.uuidString, keyString(key))
                    < (previous.kind.rawValue, previous.id.uuidString, keyString(previousKey))) else { return }
            }
            evidence = PortfolioActivityEvidence(timestamp: timestamp, kind: kind, id: id)
            physicalKey = key
        }
    }
}
#endif
