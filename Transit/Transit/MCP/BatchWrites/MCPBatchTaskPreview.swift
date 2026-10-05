#if os(macOS)
import Foundation
import SwiftData

/// Synchronous saved-local observation. No write coordinator or reservation
/// store is supplied to this boundary; only immutable values leave it.
@MainActor enum MCPBatchTaskPreview {
    nonisolated enum State: String, Sendable { case valid, invalid, unavailable }

    nonisolated struct Entry: Sendable {
        let index: Int
        let itemId: String
        let state: State
        let code: String?
        let current: MCPJSONDocument?
        let proposedEffects: MCPJSONDocument?
    }

    nonisolated struct Report: Sendable {
        let entries: [Entry]
        let observation: String
        let keyState: String
        let advisory: Bool
        let isError: Bool?
    }

    /// Descriptor seams permit spies to prove saved-only fetches even when
    /// a read fails. The milestone adapter implements the same generic seam.
    struct Reads {
        var tasks: (FetchDescriptor<TransitTask>, ModelContext) throws -> [TransitTask] = {
            try $1.fetch($0)
        }
        var comments: (FetchDescriptor<Comment>, ModelContext) throws -> [Comment] = {
            try $1.fetch($0)
        }
        var milestones: (ModelContext) -> any ModelFetching = { $0 }
    }

    static func evaluate(
        _ request: MCPBatchTaskRequest,
        container: ModelContainer, persistence: PersistenceAvailability,
        includeComments: Bool = true, reads: Reads = Reads()
    ) throws -> Report {
        guard !persistence.isFallbackStorageActive else {
            return report(request.items.map { entry($0, state: .unavailable, code: "PERSISTENCE_UNAVAILABLE") })
        }
        return try MCPBatchSavedReadContext.withContext(container: container, persistence: persistence) { context in
            let milestones = MilestoneService(modelContext: context,
                displayIDAllocator: DisplayIDAllocator(store: NoAllocation(), isCloudSyncActive: false),
                fetcher: SavedFetcher(base: reads.milestones(context)))
            return report(request.items.map {
                evaluate($0, context: context, milestones: milestones, includeComments: includeComments, reads: reads)
            })
        }
    }

    private static func report(_ entries: [Entry]) -> Report {
        Report(entries: entries, observation: "saved_local_store", keyState: "unchecked",
               advisory: true, isError: entries.allSatisfy { $0.state == .valid } ? nil : true)
    }

    private static func entry(
        _ item: MCPBatchTaskRequest.Item, state: State, code: String? = nil,
        current: MCPJSONDocument? = nil, effects: MCPJSONDocument? = nil
    ) -> Entry {
        Entry(index: item.index, itemId: item.itemId, state: state, code: code,
              current: current, proposedEffects: effects)
    }

    private static func evaluate(
        _ item: MCPBatchTaskRequest.Item, context: ModelContext, milestones: MilestoneService,
        includeComments: Bool, reads: Reads
    ) -> Entry {
        let task: TransitTask
        let snapshot: MCPRecordSnapshot
        let current: MCPJSONDocument
        do {
            let id = item.targetTaskId
            var descriptor = FetchDescriptor<TransitTask>(predicate: #Predicate { $0.id == id })
            descriptor.includePendingChanges = false
            let tasks = try reads.tasks(descriptor, context)
            guard tasks.count == 1, let resolved = tasks.first else {
                return entry(item, state: .invalid,
                    code: tasks.isEmpty ? "TASK_NOT_FOUND" : "DUPLICATE_TASK_IDENTIFIER")
            }
            task = resolved
            snapshot = try MCPRecordSnapshot.task(task, incidence: TaskLinkIncidence.capture(task.id, in: context,
                includePendingChanges: false)) { id in
                var comments = CommentService.descriptor(for: id)
                comments.includePendingChanges = false
                return try reads.comments(comments, context)
            }
            var record = snapshot.record
            if !includeComments { record.removeValue(forKey: "comments") }
            current = try document(record)
        } catch {
            // Failure obtaining required saved evidence is never a domain
            // negative answer, regardless of the injected error's type/code.
            return entry(item, state: .unavailable, code: "INTERNAL_ERROR")
        }
        if let expected = item.command.expectedRevision, expected != snapshot.revision {
            return entry(item, state: .invalid, code: "REVISION_CONFLICT", current: current)
        }
        do {
            let proposed = try effects(item.command, task: task, milestones: milestones)
            let encoded: MCPJSONDocument
            do { encoded = try document(proposed) } catch {
                return entry(item, state: .unavailable, code: "INTERNAL_ERROR", current: current)
            }
            return entry(item, state: .valid, current: current, effects: encoded)
        } catch {
            let failure = MCPWriteFailure.from(error)
            return entry(item, state: failure.code == "INTERNAL_ERROR" ? .unavailable : .invalid,
                         code: failure.code, current: current)
        }
    }

    private static func document(_ value: [String: Any]) throws -> MCPJSONDocument {
        try MCPJSONDocument.parse(JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
    }

    private static func effects(
        _ command: MCPWriteCommand, task: TransitTask, milestones: MilestoneService
    ) throws -> [String: Any] {
        if command.tool == "update_task" {
            return updateEffects(try TaskUpdateValidator.validate(
                command.arguments, task: task, milestoneService: milestones).get())
        }
        if command.tool == "add_comment" {
            let input: CommentInputValidation.Input
            do {
                input = try CommentInputValidation.normalize(
                    content: command.arguments["content"] as? String ?? "",
                    authorName: command.arguments["authorName"] as? String ?? "")
            } catch { throw MCPWriteFailure("INVALID_INPUT", "Invalid comment: \(error)") }
            return ["content": input.content, "authorName": input.authorName, "isAgent": true]
        }
        let status = try MCPTaskMutationValidation.status(currentStatus: task.statusRawValue,
            targetStatus: command.arguments["status"] as? String ?? "",
            comment: command.arguments["comment"] as? String,
            authorName: command.arguments["authorName"] as? String)
        let comment: Any = status.comment.map {
            ["content": $0.content, "authorName": $0.authorName, "isAgent": true] as [String: Any]
        } as Any? ?? NSNull()
        return ["status": status.targetStatus, "statusChanged": status.statusChanged,
                "lastStatusChange": status.lastStatusChange.rawValue,
                "completion": status.completion.rawValue, "comment": comment]
    }

    private static func updateEffects(_ update: ValidatedTaskUpdate) -> [String: Any] {
        var effects: [String: Any] = [:]
        effects["name"] = update.name
        switch update.description {
        case .noChange: break
        case .set(let value): effects["description"] = value
        case .clear: effects["description"] = NSNull()
        }
        effects["type"] = update.type?.rawValue
        effects["priority"] = update.priority?.rawValue
        switch update.metadata {
        case .noChange: break
        case .set(let value): effects["metadata"] = value
        case .clear: effects["metadata"] = NSNull()
        }
        switch update.milestoneAction {
        case .none: break
        case .assign(let milestone): effects["milestoneId"] = milestone.id.uuidString
        case .clear: effects["milestone"] = NSNull()
        }
        return effects
    }

    private struct SavedFetcher: ModelFetching {
        let base: any ModelFetching

        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
            var descriptor = descriptor
            descriptor.includePendingChanges = false
            do { return try base.fetch(descriptor) } catch { throw ReadFailure.unavailable }
        }
    }

    private enum ReadFailure: Error { case unavailable }

    /// Milestone validation needs a service dependency, but never allocation.
    /// An inert store also prevents construction from opening CloudKit access.
    nonisolated private struct NoAllocation: DisplayIDAllocator.CounterStore {
        func loadCounter() async throws -> DisplayIDAllocator.CounterSnapshot {
            throw DisplayIDAllocator.Error.cloudSyncInactive
        }

        func saveCounter(nextDisplayID: Int, expectedChangeTag: String?) async throws {
            throw DisplayIDAllocator.Error.cloudSyncInactive
        }
    }
}
#endif
