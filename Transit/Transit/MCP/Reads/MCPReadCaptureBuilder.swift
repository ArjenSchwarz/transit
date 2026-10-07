#if os(macOS)
import Foundation
import SwiftData

nonisolated enum MCPReadCaptureError: Error, Equatable {
    case incoherentCapture
    case storageFailure
    case serializationFailure
    case projectNotFound
    case ambiguousProject
}

nonisolated enum MCPReadCaptureFence: Sendable {
    case persistentHistory
    /// Tests only: one nonawaiting actor scope, no external store writers.
    case actorOnlyTestFixture
}

@MainActor
final class MCPReadCaptureBuilder: MCPReadCaptureSource {
    private var keyCache: [PersistentIdentifier: LocalRecordKey] = [:]
    private var isCapturing = false
    private let container: ModelContainer
    private let fence: MCPReadCaptureFence
    private let generation: () -> UInt64
    private let metadata: (Date, MCPReadCaptureBoundary) -> ReadCaptureMetadata
    private let fetchTasks: (ModelContext) throws -> [TransitTask]
    private let fetchMilestones: (ModelContext) throws -> [Milestone]
    private let fetchComments: (ModelContext) throws -> [Comment]
    private let afterProjects: () throws -> Void

    init(
        container: ModelContainer,
        fence: MCPReadCaptureFence = .persistentHistory,
        generation: @escaping () -> UInt64 = { 0 },
        metadata: @escaping (Date, MCPReadCaptureBoundary) -> ReadCaptureMetadata = { date, _ in
            let timestamp = MCPRecordSnapshot.timestamp(date)
            return ReadCaptureMetadata(
                asOf: timestamp, snapshotId: UUID().uuidString,
                freshness: ReadFreshness(syncState: .inactive, assessment: .notApplicable,
                                         assessedAt: timestamp, lastImportedAt: nil, evidence: .none,
                                         recentImportThresholdMs: 30_000),
                read: ReadExecutionMetadata(policy: .cached, refreshOutcome: .notRequested, budgetMs: 5_000))
        },
        fetchComments: @escaping (ModelContext) throws -> [Comment] = {
            try $0.fetch(FetchDescriptor<Comment>())
        },
        afterProjects: @escaping () throws -> Void = {},
        fetchTasks: @escaping (ModelContext) throws -> [TransitTask] = {
            try $0.fetch(FetchDescriptor<TransitTask>())
        },
        fetchMilestones: @escaping (ModelContext) throws -> [Milestone] = {
            try $0.fetch(FetchDescriptor<Milestone>())
        }
    ) {
        self.container = container
        self.fence = fence
        self.generation = generation
        self.metadata = metadata
        self.fetchComments = fetchComments
        self.fetchTasks = fetchTasks
        self.fetchMilestones = fetchMilestones
        self.afterProjects = afterProjects
    }

    func capture(_ request: ReadCaptureRequest) throws -> CapturedReadView {
        guard !isCapturing else { throw MCPReadCaptureError.incoherentCapture }
        guard request.completeness != .completePortfolio
            || (request.selectTaskBodies == nil && request.selectMilestoneBodies == nil
                && request.consolidationTarget == nil) else {
            throw MCPReadCaptureError.incoherentCapture
        }
        isCapturing = true
        defer { isCapturing = false; keyCache.removeAll(keepingCapacity: false) }
        try request.taskLinkBudget?.check()
        let initialGeneration = generation()
        let before = try watermark()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let instant = ContinuousClock.now
        let evaluationInstant = Date()
        let copied = try copy(request, in: context, evaluationInstant: evaluationInstant)
        let after = try watermark()
        guard initialGeneration == generation(), before?.token == after?.token,
              before?.storeIdentifier == after?.storeIdentifier else {
            throw MCPReadCaptureError.incoherentCapture
        }
        let view = CapturedReadView(
            completeness: request.completeness, captureScope: copied.scope,
            metadata: metadata(evaluationInstant, MCPReadCaptureBoundary(
                historyStoreIdentifier: after?.storeIdentifier, generation: initialGeneration,
                stablePersistentHistory: fence == .persistentHistory)), createdAt: instant,
            retentionDeadline: instant + .seconds(300), projects: copied.projects,
            tasks: copied.tasks, milestones: copied.milestones, comments: copied.comments,
            taskLinkGraph: copied.taskLinkGraph, consolidationEvidence: copied.consolidationEvidence)
        if view.completeness == .completePortfolio { try MCPReadCaptureValidation.validateReusableCapture(view) }
        try request.taskLinkBudget?.check()
        return view
    }
    private func watermark() throws -> DefaultHistoryTransaction? {
        guard fence == .persistentHistory else { return nil }
        do { return try SavedReadBoundary.watermark(container) } catch { throw MCPReadCaptureError.incoherentCapture }
    }
    private typealias Copied = MCPReadCopiedValues
    private func copy(
        _ request: ReadCaptureRequest, in context: ModelContext, evaluationInstant: Date
    ) throws -> Copied {
        do {
            let projects = try context.fetch(FetchDescriptor<Project>())
            try request.validateProjects?(projects.map { ReadProjectIdentity(id: $0.id, name: $0.name) })
            let selected = try resolve(request.projectSelectors, projects: projects)
            let selectedKeys = try Set(selected.map(key))
            try afterProjects()
            let entities = try fetchEntities(request, in: context)
            let (allTasks, allMilestones) = (entities.tasks, entities.milestones)
            let graph = try TaskLinkCaptureIntegration.graph(request, in: context, entities, at: evaluationInstant)
            let tasks = try allTasks.filter { task in
                guard request.projectSelectors != nil else { return true }
                return try task.project.map { selectedKeys.contains(try key($0)) } ?? false
            }
            let milestones = try scopedMilestones(allMilestones, request: request, keys: selectedKeys)
            let consolidationSelection = try request.consolidationTarget?.resolve(in: context,
                budget: request.taskLinkBudget ?? TaskLinkGraphBudget())
            let bodyKeys = try bodyKeys(request, tasks: tasks, selection: consolidationSelection, graph: graph)
            let milestoneBodyKeys = try milestoneBodyKeys(request, all: allMilestones, scoped: milestones)
            let bodyTasks = try tasks.filter { bodyKeys.contains(try key($0)) }
            let full = fullRecordSelection(request.selection)
            guard request.completeness != .completePortfolio || full else {
                throw MCPReadCaptureError.incoherentCapture
            }
            let comments = try commentEvidence(request, context: context, bodyTasks: bodyTasks,
                                               needed: full || request.includeComments)
            let includedComments = commentsForScope(comments, request: request, tasks: bodyTasks)
            let commentValues = try indexComments(includedComments)
            // Freeze identity closure separately; it never changes the declared selected scope.
            let scope = request.captureScope(selectedKeys: selectedKeys)
            // Freeze borrowed ordinary records before supplementary context refetches.
            let copied = try Copied(scope: scope, projects: projects.map(projectValue),
                              tasks: copyTaskValues(request.completeness == .completePortfolio ? allTasks : tasks,
                                  selectedKeys: bodyKeys, comments: commentValues.index,
                                  full: full, includeComments: request.includeComments,
                                  graph: graph, budget: request.taskLinkBudget),
                              milestones: (request.completeness == .completePortfolio
                                  ? allMilestones : milestones).map {
                                      try milestoneValue($0, canonical: milestoneBodyKeys.contains(try key($0)))
                                  },
                              comments: commentValues.values, taskLinkGraph: graph,
                              consolidationEvidence: nil)
            return copied.retaining(try consolidationEvidence(request, context: context, tasks: bodyTasks,
                graph: graph, selection: consolidationSelection))
        } catch let error as MCPTaskQueryError {
            throw error
        } catch let error where preservesCaptureFailure(error) {
            throw error
        } catch is MCPCanonicalJSON.Error {
            throw MCPReadCaptureError.serializationFailure
        } catch {
            throw MCPReadCaptureError.storageFailure
        }
    }
    private func preservesCaptureFailure(_ error: Error) -> Bool {
        error is TaskLinkGraphError || error is MCPReadCaptureError || error is ConsolidationSelectionFailure
            || error is ConsolidationPlanningError || error is TaskConsolidationHistoryError
    }

    private func bodyKeys(_ request: ReadCaptureRequest, tasks: [TransitTask],
                          selection: ConsolidationCaptureSelection?, graph: TaskLinkGraphView?) throws
        -> Set<LocalRecordKey> {
        if let selection {
            return Set(try tasks.filter { selection.selectedTaskIds.contains($0.id) }.map(key))
        }
        return try request.taskBodyKeys(tasks.map(taskSelectionValue), graph: graph)
    }

    private func scopedMilestones(_ values: [Milestone], request: ReadCaptureRequest,
                                  keys: Set<LocalRecordKey>) throws -> [Milestone] {
        try values.filter { milestone in
            guard request.projectSelectors != nil else { return true }
            return try milestone.project.map { keys.contains(try key($0)) } ?? false
        }
    }

    private func consolidationEvidence(_ request: ReadCaptureRequest, context: ModelContext,
                                       tasks: [TransitTask], graph: TaskLinkGraphView?,
                                       selection: ConsolidationCaptureSelection?) throws
        -> ConsolidationSavedEvidence? {
        guard fullRecordSelection(request.selection), request.selection.requiredEntities.0 else { return nil }
        guard let graph else {
            guard tasks.isEmpty && selection == nil else { throw MCPReadCaptureError.incoherentCapture }
            return nil // The resolved ordinary selection deliberately required no task fetch.
        }
        return try TaskConsolidationSavedCapture(container: container).copy(
            selection ?? .init(selectedTaskIds: tasks.map(\.id), requireSelectedOriginals: false),
            in: context, graph: graph, budget: request.taskLinkBudget ?? TaskLinkGraphBudget())
    }

    private func resolve(_ selectors: [ReadProjectSelector]?, projects: [Project]) throws -> [Project] {
        guard let selectors else { return projects }
        return try selectors.map { selector in
            let matches = projects.filter { project in
                switch selector {
                case .id(let id): project.id == id
                case .name(let name): ProjectNamePolicy.normalized(project.name) == ProjectNamePolicy.normalized(name)
                }
            }
            guard let match = matches.first else { throw MCPReadCaptureError.projectNotFound }
            guard matches.count == 1 else { throw MCPReadCaptureError.ambiguousProject }
            return match
        }
    }

    private func json(_ value: Any) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        } catch {
            throw MCPReadCaptureError.serializationFailure
        }
    }

    private func milestoneValue(_ milestone: Milestone, canonical: Bool) throws -> ReadMilestone {
        try ReadMilestone(physicalKey: key(milestone), id: milestone.id,
                          permanentDisplayId: milestone.permanentDisplayId, name: milestone.name,
                          milestoneDescription: milestone.milestoneDescription,
                          projectKey: milestone.project.map(key), storedProjectID: milestone.project?.id,
                          rawStatus: milestone.statusRawValue, effectiveStatus: milestone.status.rawValue,
                          creationDate: milestone.creationDate, lastStatusChangeDate: milestone.lastStatusChangeDate,
                          completionDate: milestone.completionDate, taskKeys: (milestone.tasks ?? []).map(key),
                          selectedRecordJSON: json(canonical ? MCPRecordSnapshot.milestone(milestone).record
                            : ["milestoneId": milestone.id.uuidString, "name": milestone.name]))
    }

    private func commentValue(_ comment: Comment) throws -> ReadCommentEvidence {
        try ReadCommentEvidence(physicalKey: key(comment), id: comment.id, taskKey: comment.task.map(key),
                                storedTaskID: comment.task?.id, creationDate: comment.creationDate,
                                content: comment.content, authorName: comment.authorName, isAgent: comment.isAgent,
                                selectedRecordJSON: json(MCPRecordSnapshot.comment(comment).record))
    }

    // Explicit frozen graph evidence accompanies the existing task/comment projection controls.
    // swiftlint:disable:next function_parameter_count
    private func taskValue(
        _ task: TransitTask, comments: TaskComments, full: Bool, includeComments: Bool,
        identityOnly: Bool, graph: TaskLinkGraphView?
    ) throws -> ReadTask {
        let coveredComments = comments.canonical
        let taskKey = try key(task)
        let ownedComments = comments.owned
        let snapshot = full && !identityOnly
            ? try MCPRecordSnapshot.task(task, incidence: graph.map { $0.incidence[task.id, default: []] },
                                         budget: comments.budget) { _ in coveredComments } : nil
        var noComments = snapshot?.record
        noComments?.removeValue(forKey: "comments")
        var selected = noComments ?? ["taskId": task.id.uuidString, "name": task.name,
                                      "status": task.status.rawValue, "type": task.type.rawValue,
                                      "priority": task.priority.rawValue]
        if identityOnly { selected = ["taskId": task.id.uuidString, "name": task.name] }
        if includeComments && !identityOnly {
            selected["comments"] = try coveredComments.map { try MCPRecordSnapshot.comment($0).record }
        }
        return try ReadTask(
            physicalKey: taskKey, id: task.id, permanentDisplayId: task.permanentDisplayId,
            name: task.name, taskDescription: identityOnly ? nil : task.taskDescription,
            projectKey: task.project.map(key),
            milestoneKey: task.milestone.map(key), storedProjectID: task.project?.id,
            storedMilestoneID: task.milestone?.id, rawStatus: task.statusRawValue,
            effectiveStatus: task.status.rawValue, rawType: task.typeRawValue, effectiveType: task.type.rawValue,
            rawPriority: task.priorityRawValue, effectivePriority: task.priority.rawValue,
            metadata: identityOnly ? [:] : task.metadata, metadataJSON: identityOnly ? nil : task.metadataJSON,
            creationDate: task.creationDate,
            lastStatusChangeDate: task.lastStatusChangeDate, completionDate: task.completionDate,
            commentKeys: ownedComments.map(key), selectedRecordJSON: json(selected), revision: snapshot?.revision,
            fullRecordWithoutCommentsJSON: noComments.map(json),
            requestedCommentRecordsJSON: includeComments && !identityOnly
                ? json(coveredComments.map { try MCPRecordSnapshot.comment($0).record }) : nil)
    }
}
private extension MCPReadCaptureBuilder {
    private func projectValue(_ project: Project) throws -> ReadProject {
        try ReadProject(physicalKey: key(project), id: project.id, name: project.name,
                        projectDescription: project.projectDescription, gitRepo: project.gitRepo,
                        colorHex: project.colorHex, taskKeys: (project.tasks ?? []).map(key),
                        milestoneKeys: (project.milestones ?? []).map(key),
                        selectedRecordJSON: json(MCPRecordSnapshot.project(project).record))
    }

    private func milestoneBodyKeys(_ request: ReadCaptureRequest, all: [Milestone],
                                   scoped: [Milestone]) throws -> Set<LocalRecordKey> {
        if let select = request.selectMilestoneBodies {
            return try select(all.map {
                ReadMilestoneSelectionValue(physicalKey: try key($0), identity: milestoneIdentity($0))
            })
        }
        let values = request.completeness == .completePortfolio && request.projectSelectors != nil ? scoped : all
        return try Set(values.map(key))
    }

    private func fullRecordSelection(_ selection: ReadCaptureSelection) -> Bool {
        switch selection {
        case .portfolio, .tasks(detail: .fullRecord): true
        default: false
        }
    }

    private func commentEvidence(_ request: ReadCaptureRequest, context: ModelContext,
                                 bodyTasks: [TransitTask], needed: Bool) throws -> [Comment] {
        // A selected empty result needs no comments. Complete portfolio still requires
        // the full orphan/comment diagnostic domain, including an empty task domain.
        guard request.selection.requiredEntities.0 && needed,
              request.completeness == .completePortfolio || !bodyTasks.isEmpty else { return [] }
        return try fetchComments(context)
    }

    private func key(_ model: some PersistentModel) throws -> LocalRecordKey {
        let identifier = model.persistentModelID
        if let cached = keyCache[identifier] { return cached }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let encoded = LocalRecordKey(encodedIdentifier: try encoder.encode(identifier))
            keyCache[identifier] = encoded
            return encoded
        } catch {
            throw MCPReadCaptureError.serializationFailure
        }
    }

    private func taskSelectionValue(_ task: TransitTask) throws -> ReadTaskSelectionValue {
        try ReadTaskSelectionValue(physicalKey: key(task), id: task.id, permanentDisplayId: task.permanentDisplayId,
            name: task.name, taskDescription: task.taskDescription, storedProjectID: task.project?.id,
            storedMilestoneID: task.milestone?.id, rawStatus: task.statusRawValue, rawType: task.typeRawValue,
            effectivePriority: task.priority.rawValue)
    }

    private func milestoneIdentity(_ milestone: Milestone) -> ReadMilestoneIdentity {
        ReadMilestoneIdentity(id: milestone.id, permanentDisplayId: milestone.permanentDisplayId, name: milestone.name,
            storedProjectID: milestone.project?.id, rawStatus: milestone.statusRawValue,
            milestoneDescription: milestone.milestoneDescription)
    }

    func fetchEntities(_ request: ReadCaptureRequest, in context: ModelContext)
        throws -> ReadCaptureFetchedEntities {
        let (needsTasks, needsMilestones) = request.selection.requiredEntities
        let allMilestones = needsMilestones ? try fetchMilestones(context) : []
        let needsTaskValues = try request.validateMilestones?(allMilestones.map {
            milestoneIdentity($0)
        }) ?? needsTasks
        let allTasks = needsTasks && needsTaskValues ? try fetchTasks(context) : []
        return ReadCaptureFetchedEntities(tasks: allTasks, milestones: allMilestones,
                                          tasksCaptured: needsTasks && needsTaskValues)
    }
    func commentsForScope(_ comments: [Comment], request: ReadCaptureRequest, tasks: [TransitTask]) -> [Comment] {
        if request.completeness == .completePortfolio && request.projectSelectors == nil { return comments }
        let ids = Set(tasks.map(\.id))
        return comments.filter {
            $0.task.map { ids.contains($0.id) } ?? (request.completeness == .completePortfolio)
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func copyTaskValues(_ tasks: [TransitTask], selectedKeys: Set<LocalRecordKey>, comments: CommentIndex,
                                full: Bool, includeComments: Bool, graph: TaskLinkGraphView?,
                                budget: TaskLinkGraphBudget?) throws -> [ReadTask] {
        try tasks.map { task in
            let taskKey = try key(task)
            return try taskValue(task, comments: TaskComments(canonical: comments.canonical[task.id] ?? [],
                                                            owned: comments.physical[taskKey] ?? [], budget: budget),
                                 full: full, includeComments: includeComments,
                                 identityOnly: !selectedKeys.contains(taskKey), graph: graph)
        }
    }

    private struct CommentIndex {
        let canonical: [UUID: [Comment]]
        let physical: [LocalRecordKey: [Comment]]
    }

    private func indexComments(_ includedComments: [Comment]) throws
        -> (index: CommentIndex, values: [ReadCommentEvidence]) {
        let canonicalComments = Dictionary(grouping: includedComments.compactMap { comment in
            comment.task.map { ($0.id, comment) }
        }, by: { $0.0 }).mapValues { group in
            group.map(\.1).sorted { ($0.creationDate, $0.id.uuidString) < ($1.creationDate, $1.id.uuidString) }
        }
        var physicalComments: [LocalRecordKey: [Comment]] = [:]
        for comment in includedComments {
            if let owner = comment.task { physicalComments[try key(owner), default: []].append(comment) }
        }
        return (CommentIndex(canonical: canonicalComments, physical: physicalComments),
            try includedComments.map(commentValue))
    }

    private struct TaskComments {
        let canonical: [Comment]
        let owned: [Comment]
        let budget: TaskLinkGraphBudget?
    }
}
#endif
