#if os(macOS)
import Foundation

/// Ordered execution over original protected-command evidence. The complete
/// prepared fallback capability is required before any item can be dispatched.
@MainActor final class MCPBatchTaskCoordinator {
    nonisolated struct Execution: Sendable {
        let source: MCPResultSource
        let pendingEditsStop: Bool

        init(source: MCPResultSource, pendingEditsStop: Bool = false) {
            self.source = source
            self.pendingEditsStop = pendingEditsStop
        }
    }

    nonisolated enum State: String, Sendable { case attempted, notAttempted = "not_attempted" }
    nonisolated enum Reason: String, Sendable {
        case itemResult = "item_result", evidenceUnavailable = "evidence_unavailable"
        case pendingEdits = "pending_edits", cancelled
    }
    nonisolated struct Blocker: Sendable, Equatable {
        let index: Int
        let itemId: String
    }
    nonisolated struct Stop: Sendable {
        let reason: Reason
        let nextUnstartedIndex: Int
        let blocker: Blocker?
    }
    nonisolated struct Entry: Sendable {
        let index: Int
        let itemId: String
        let operation: String
        let originalKey: String
        let taskID: UUID
        let state: State
        let originalResult: MCPResultSource?
    }
    nonisolated struct Report: Sendable {
        let summary: String
        let confirmedCommittedCount: Int
        let entries: [Entry]
        let stop: Stop?
        let observedCancellation: Bool
        let isError: Bool?
    }
    nonisolated enum Error: Swift.Error, Sendable, Equatable { case preparedRequestMismatch, executeModeRequired }
    typealias Executor = @MainActor (MCPBatchTaskRequest.Item) async throws -> Execution
    private let preparedResponse: MCPBatchTaskPreparedResponse
    private let executor: Executor
    private let observedCancellation: @MainActor () -> Bool

    init(preparedResponse: MCPBatchTaskPreparedResponse, executor: @escaping Executor,
         observedCancellation: @escaping @MainActor () -> Bool = { Task.isCancelled }) {
        self.preparedResponse = preparedResponse
        self.executor = executor
        self.observedCancellation = observedCancellation
    }

    func run(_ request: MCPBatchTaskRequest) async throws -> Report {
        guard request.mode == .execute else { throw Error.executeModeRequired }
        try validatePreparedIdentity(request)
        var entries = request.items.map { entry($0, source: nil, attempted: false) }
        var committed = 0
        var cancelled = false
        for item in request.items {
            cancelled = observedCancellation() || cancelled
            if cancelled {
                return report("interrupted", committed: committed, entries: entries,
                    stop: Stop(reason: .cancelled, nextUnstartedIndex: item.index, blocker: nil), cancelled: true)
            }
            let execution: Execution
            do { execution = try await executor(item) } catch {
                entries[item.index] = entry(item, source: nil, attempted: true)
                cancelled = observedCancellation() || cancelled
                return stopped(item, reason: .evidenceUnavailable, committed: committed,
                               entries: entries, cancelled: cancelled)
            }
            entries[item.index] = entry(item, source: execution.source, attempted: true)
            let comment = item.command.arguments["comment"] as? String
            let assessment = MCPBatchTaskEvidence.assess(source: execution.source,
                operation: item.operation, originalKey: item.command.key, taskID: item.targetTaskId,
                requiresStatusComment: item.operation == "update_task_status" &&
                    comment?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            cancelled = observedCancellation() || cancelled
            switch assessment.kind {
            case .committed: committed += 1
            case .unavailable:
                return stopped(item, reason: .evidenceUnavailable, committed: committed,
                               entries: entries, cancelled: cancelled)
            case .itemResult:
                return stopped(item, reason: execution.pendingEditsStop ? .pendingEdits : .itemResult,
                               committed: committed, entries: entries, cancelled: cancelled)
            }
        }
        return report("all_committed", committed: committed, entries: entries, stop: nil, cancelled: cancelled)
    }

    private func validatePreparedIdentity(_ request: MCPBatchTaskRequest) throws {
        guard case .applicationBatch(let recovery) = preparedResponse.context.mutationRecovery,
              recovery.count == request.items.count else { throw Error.preparedRequestMismatch }
        for (index, pair) in zip(request.items, recovery).enumerated() {
            let (item, retained) = pair
            guard item.index == index, retained.index == index,
                  retained.operation.utf8.elementsEqual(item.operation.utf8),
                  retained.originalKey.tool.utf8.elementsEqual(item.command.tool.utf8),
                  retained.originalKey.idempotencyKey.utf8.elementsEqual(item.command.key.utf8),
                  retained.targetTaskId == item.targetTaskId else { throw Error.preparedRequestMismatch }
        }
    }

    private func entry(_ item: MCPBatchTaskRequest.Item, source: MCPResultSource?, attempted: Bool) -> Entry {
        Entry(index: item.index, itemId: item.itemId, operation: item.operation, originalKey: item.command.key,
              taskID: item.targetTaskId, state: attempted ? .attempted : .notAttempted, originalResult: source)
    }

    private func stopped(
        _ item: MCPBatchTaskRequest.Item, reason: Reason, committed: Int, entries: [Entry], cancelled: Bool
    ) -> Report {
        report(reason == .evidenceUnavailable ? "evidence_unavailable" : "stopped",
            committed: committed, entries: entries,
            stop: Stop(reason: reason, nextUnstartedIndex: item.index + 1,
                       blocker: Blocker(index: item.index, itemId: item.itemId)), cancelled: cancelled)
    }

    private func report(
        _ summary: String, committed: Int, entries: [Entry], stop: Stop?, cancelled: Bool
    ) -> Report {
        Report(summary: summary, confirmedCommittedCount: committed, entries: entries,
               stop: stop, observedCancellation: cancelled, isError: stop == nil ? nil : true)
    }

}
#endif
