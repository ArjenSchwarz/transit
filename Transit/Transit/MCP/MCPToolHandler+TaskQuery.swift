#if os(macOS)
import Foundation
import SwiftData

extension MCPToolHandler {
    func handleQueryTasks(_ args: [String: Any]) -> MCPToolResult {
        do {
            guard taskQueryAdmissionOpen else {
                throw MCPTaskQueryError(code: "QUERY_UNAVAILABLE",
                                        message: "Query unavailable; retry when server is running")
            }
            let request = try MCPTaskQueryRequest.parse(args)
            taskQuerySnapshots.purgeExpired()
            if let cursor = request.cursor { return textResult(try taskQuerySnapshots.page(for: cursor)) }
            let deadline = taskQuerySnapshots.now().advanced(by: .seconds(300))
            let expiry = taskQuerySnapshots.wallNow().addingTimeInterval(300)
            let results = try queryResults(request, args: args)
            return textResult(try encodeQueryPages(results, limit: request.limit, expiry: expiry, deadline: deadline))
        } catch let error as MCPTaskQueryError {
            return queryErrorResult(error)
        } catch {
            return queryErrorResult(MCPTaskQueryError(code: "QUERY_FAILED", message: "Query failed: \(error)"))
        }
    }

    private func queryErrorResult(_ error: MCPTaskQueryError) -> MCPToolResult {
        let category = MCPResultClassification.category(for: error.code) ?? .unclassifiedHistorical
        return errorResult(IntentHelpers.encodeJSON(["error": ["code": error.code, "message": error.message]]),
            category: category, origin: .generatedJSON)
    }

    private func queryResults(_ request: MCPTaskQueryRequest, args: [String: Any]) throws -> [[String: Any]] {
        // Preserve injected fetch failure behavior without returning borrowed UI values.
        do { _ = try taskFetcher.fetchAllTasks() } catch {
            throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Failed to fetch tasks: \(error)")
        }
        let budget = TaskLinkGraphBudget()
        let capture = ReadCaptureRequest(projectSelectors: nil,
            selection: .tasks(detail: request.detailLevel == "full" ? .fullRecord : .summary),
            completeness: .selectedRead, includeComments: request.includeComments, taskLinkBudget: budget)
        let view = try MCPReadCaptureBuilder(container: taskService.savedReadContainer).capture(capture)
        let records = try MCPReadProjection.tasks(view, request: request, arguments: args, budget: budget)
        if request.detailLevel == "full" || request.includeComments {
            var checked: Set<UUID> = []
            for value in records {
                try budget.check()
                let record = value["task"] as? [String: Any] ?? value
                if let raw = record["taskId"] as? String, let id = UUID(uuidString: raw), checked.insert(id).inserted {
                    do { _ = try commentFetcher.fetchComments(for: id) } catch {
                        throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Failed to fetch comments: \(error)")
                    }
                }
            }
        }
        return records
    }

    func encodeQueryPages(
        _ results: [[String: Any]], limit: Int, expiry: Date, deadline: ContinuousClock.Instant
    ) throws -> String {
        let count = max(1, (results.count + limit - 1) / limit)
        let cursors = (0..<(count - 1)).map { _ in taskQuerySnapshots.makeCursor() }
        let expiryText = ISO8601DateFormatter().string(from: expiry)
        var pages: [String] = []
        var bytes = 0
        for position in 0..<count {
            let start = position * limit
            let end = min(start + limit, results.count)
            let next: Any = position < cursors.count ? cursors[position] : NSNull()
            let payload: [String: Any] = ["results": Array(results[start..<end]),
                                          "nextCursor": next, "expiresAt": expiryText]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            bytes += data.count
            guard bytes <= taskQuerySnapshots.maxBytes else { throw taskQuerySnapshots.capacityError() }
            guard let text = String(data: data, encoding: .utf8) else {
                throw MCPTaskQueryError(code: "QUERY_FAILED", message: "Could not encode query page")
            }
            pages.append(text)
        }
        try taskQuerySnapshots.publish(pages: pages, cursors: cursors, deadline: deadline)
        return pages[0]
    }

}
#endif
