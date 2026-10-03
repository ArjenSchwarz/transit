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
    private let container: ModelContainer
    private let fence: MCPReadCaptureFence
    private let generation: () -> UInt64
    private let metadata: (Date, MCPReadCaptureBoundary) -> ReadCaptureMetadata
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
        afterProjects: @escaping () throws -> Void = {}
    ) {
        self.container = container
        self.fence = fence
        self.generation = generation
        self.metadata = metadata
        self.fetchComments = fetchComments
        self.afterProjects = afterProjects
    }

    func capture(_ request: ReadCaptureRequest) throws -> CapturedReadView {
        let initialGeneration = generation()
        let before = try watermark()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let copied = try copy(request, in: context)
        let after = try watermark()
        guard initialGeneration == generation(), before?.token == after?.token,
              before?.storeIdentifier == after?.storeIdentifier else {
            throw MCPReadCaptureError.incoherentCapture
        }
        let instant = ContinuousClock.now
        return CapturedReadView(
            completeness: request.completeness, captureScope: copied.scope,
            metadata: metadata(Date(), MCPReadCaptureBoundary(
                historyStoreIdentifier: after?.storeIdentifier, generation: initialGeneration,
                stablePersistentHistory: fence == .persistentHistory)), createdAt: instant,
            retentionDeadline: instant + .seconds(300), projects: copied.projects,
            tasks: copied.tasks, milestones: copied.milestones, comments: copied.comments)
    }

    private func watermark() throws -> DefaultHistoryTransaction? {
        guard fence == .persistentHistory else { return nil }
        guard container.configurations.count == 1 else { throw MCPReadCaptureError.incoherentCapture }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            var descriptor = HistoryDescriptor<DefaultHistoryTransaction>(
                sortBy: [SortDescriptor(\.transactionIdentifier, order: .reverse)])
            descriptor.fetchLimit = 1
            if let transaction = try context.fetchHistory(descriptor).first {
                guard !transaction.storeIdentifier.isEmpty else { throw MCPReadCaptureError.incoherentCapture }
                return transaction
            }
            // An empty selection does not prove an empty store. History can have been purged.
            guard try context.fetchCount(FetchDescriptor<Project>()) == 0,
                  try context.fetchCount(FetchDescriptor<TransitTask>()) == 0,
                  try context.fetchCount(FetchDescriptor<Milestone>()) == 0,
                  try context.fetchCount(FetchDescriptor<Comment>()) == 0,
                  try context.fetchCount(FetchDescriptor<SyncHeartbeat>()) == 0,
                  try context.fetchCount(FetchDescriptor<MCPWriteReceipt>()) == 0 else {
                throw MCPReadCaptureError.incoherentCapture
            }
            return nil
        } catch {
            throw MCPReadCaptureError.incoherentCapture
        }
    }

    private struct Copied {
        let scope: ReadCaptureScope
        let projects: [ReadProject]
        let tasks: [ReadTask]
        let milestones: [ReadMilestone]
        let comments: [ReadCommentEvidence]
    }

    private func copy(_ request: ReadCaptureRequest, in context: ModelContext) throws -> Copied {
        do {
            let projects = try context.fetch(FetchDescriptor<Project>())
            let selected = try resolve(request.projectSelectors, projects: projects)
            let selectedKeys = try Set(selected.map(key))
            try afterProjects()
            let (needsTasks, needsMilestones) = neededEntities(request.selection)
            let allTasks = needsTasks ? try context.fetch(FetchDescriptor<TransitTask>()) : []
            let allMilestones = needsMilestones ? try context.fetch(FetchDescriptor<Milestone>()) : []
            let tasks = try allTasks.filter { task in
                guard request.projectSelectors != nil else { return true }
                return try task.project.map { selectedKeys.contains(try key($0)) } ?? false
            }
            let milestones = try allMilestones.filter { milestone in
                guard request.projectSelectors != nil else { return true }
                return try milestone.project.map { selectedKeys.contains(try key($0)) } ?? false
            }
            let full: Bool
            switch request.selection {
            case .portfolio, .tasks(detail: .fullRecord): full = true
            default: full = false
            }
            guard request.completeness != .completePortfolio || full else {
                throw MCPReadCaptureError.incoherentCapture
            }
            let comments = needsTasks && (full || request.includeComments) ? try fetchComments(context) : []
            let includedComments = request.completeness == .completePortfolio ? comments
                : comments.filter { comment in tasks.contains { $0.id == comment.task?.id } }
            // Freeze identity closure separately; it never changes the declared selected scope.
            let scope: ReadCaptureScope = request.completeness == .completePortfolio
                ? (request.projectSelectors == nil ? .wholePortfolio : .projects(selectedKeys.sorted(by: keyOrder)))
                : .selectedQuery
            return try Copied(scope: scope, projects: projects.map(projectValue),
                              tasks: (request.completeness == .completePortfolio ? allTasks : tasks).map {
                                  try taskValue($0, comments: includedComments, full: full,
                                                             includeComments: request.includeComments) },
                              milestones: (request.completeness == .completePortfolio
                                  ? allMilestones : milestones).map(milestoneValue),
                              comments: includedComments.map(commentValue))
        } catch let error as MCPReadCaptureError {
            throw error
        } catch is MCPCanonicalJSON.Error {
            throw MCPReadCaptureError.serializationFailure
        } catch {
            throw MCPReadCaptureError.storageFailure
        }
    }

    private func neededEntities(_ selection: ReadCaptureSelection) -> (Bool, Bool) {
        switch selection {
        case .projects: (false, false)
        case .milestones: (false, true)
        case .tasks, .portfolio: (true, true)
        }
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

    private func key(_ model: some PersistentModel) throws -> LocalRecordKey {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return LocalRecordKey(encodedIdentifier: try encoder.encode(model.persistentModelID))
        } catch {
            throw MCPReadCaptureError.serializationFailure
        }
    }

    private func keyOrder(_ lhs: LocalRecordKey, _ rhs: LocalRecordKey) -> Bool {
        lhs.encodedIdentifier.lexicographicallyPrecedes(rhs.encodedIdentifier)
    }

    private func json(_ value: Any) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        } catch {
            throw MCPReadCaptureError.serializationFailure
        }
    }

    private func projectValue(_ project: Project) throws -> ReadProject {
        try ReadProject(physicalKey: key(project), id: project.id, name: project.name,
                        projectDescription: project.projectDescription, gitRepo: project.gitRepo,
                        colorHex: project.colorHex, taskKeys: (project.tasks ?? []).map(key),
                        milestoneKeys: (project.milestones ?? []).map(key),
                        selectedRecordJSON: json(MCPRecordSnapshot.project(project).record))
    }

    private func milestoneValue(_ milestone: Milestone) throws -> ReadMilestone {
        try ReadMilestone(physicalKey: key(milestone), id: milestone.id,
                          permanentDisplayId: milestone.permanentDisplayId, name: milestone.name,
                          milestoneDescription: milestone.milestoneDescription,
                          projectKey: milestone.project.map(key), storedProjectID: milestone.project?.id,
                          rawStatus: milestone.statusRawValue, effectiveStatus: milestone.status.rawValue,
                          creationDate: milestone.creationDate, lastStatusChangeDate: milestone.lastStatusChangeDate,
                          completionDate: milestone.completionDate, taskKeys: (milestone.tasks ?? []).map(key),
                          selectedRecordJSON: json(MCPRecordSnapshot.milestone(milestone).record))
    }

    private func commentValue(_ comment: Comment) throws -> ReadCommentEvidence {
        try ReadCommentEvidence(physicalKey: key(comment), id: comment.id, taskKey: comment.task.map(key),
                                storedTaskID: comment.task?.id, creationDate: comment.creationDate,
                                content: comment.content, authorName: comment.authorName, isAgent: comment.isAgent,
                                selectedRecordJSON: json(MCPRecordSnapshot.comment(comment).record))
    }

    private func taskValue(
        _ task: TransitTask, comments: [Comment], full: Bool, includeComments: Bool
    ) throws -> ReadTask {
        let coveredComments = comments.filter { $0.task?.id == task.id }.sorted {
            ($0.creationDate, $0.id.uuidString) < ($1.creationDate, $1.id.uuidString)
        }
        let taskKey = try key(task)
        let ownedComments = try comments.filter { comment in
            try comment.task.map { try key($0) == taskKey } ?? false
        }
        let snapshot = full ? try MCPRecordSnapshot.task(task) { _ in coveredComments } : nil
        var noComments = snapshot?.record
        noComments?.removeValue(forKey: "comments")
        var selected = noComments ?? ["taskId": task.id.uuidString, "name": task.name,
                                      "status": task.status.rawValue, "type": task.type.rawValue,
                                      "priority": task.priority.rawValue]
        if includeComments {
            selected["comments"] = try coveredComments.map { try MCPRecordSnapshot.comment($0).record }
        }
        return try ReadTask(
            physicalKey: taskKey, id: task.id, permanentDisplayId: task.permanentDisplayId,
            name: task.name, taskDescription: task.taskDescription, projectKey: task.project.map(key),
            milestoneKey: task.milestone.map(key), storedProjectID: task.project?.id,
            storedMilestoneID: task.milestone?.id, rawStatus: task.statusRawValue,
            effectiveStatus: task.status.rawValue, rawType: task.typeRawValue, effectiveType: task.type.rawValue,
            rawPriority: task.priorityRawValue, effectivePriority: task.priority.rawValue,
            metadata: task.metadata, metadataJSON: task.metadataJSON, creationDate: task.creationDate,
            lastStatusChangeDate: task.lastStatusChangeDate, completionDate: task.completionDate,
            commentKeys: ownedComments.map(key), selectedRecordJSON: json(selected), revision: snapshot?.revision,
            fullRecordWithoutCommentsJSON: noComments.map(json),
            requestedCommentRecordsJSON: includeComments
                ? json(coveredComments.map { try MCPRecordSnapshot.comment($0).record }) : nil)
    }
}
#endif
