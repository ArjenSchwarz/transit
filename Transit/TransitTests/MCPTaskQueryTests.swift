#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPTaskQueryTests {
    private func call(_ env: MCPTestEnv, _ fields: [String: Any]) async -> JSONRPCResponse? {
        await env.handler.handle(MCPTestHelpers.toolCallRequest(tool: "query_tasks", arguments: fields))
    }

    @Test func frozen182ChoresAndReplay() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        var tasks: [TransitTask] = []
        for index in 0..<182 {
            let task = TransitTask(name: "Chore \(index)", type: .chore, project: project, displayID: .provisional)
            task.taskDescription = "Description \(index)"
            env.context.insert(task)
            tasks.append(task)
        }
        try env.context.save()
        let expected = tasks.sorted { $0.id.uuidString < $1.id.uuidString }
        let first = try MCPTestHelpers.decodeResult(await call(env, [
            "type": "chore", "detailLevel": "full", "includeComments": false, "limit": 100
        ]))
        let cursor = try #require(first["nextCursor"] as? String)
        let firstResults = try #require(first["results"] as? [[String: Any]])
        #expect(firstResults.count == 100)
        let descriptions = expected.map(\.taskDescription)
        for task in tasks { task.taskDescription = "Edited" }
        env.context.delete(expected.last!)
        env.context.insert(TransitTask(name: "New", type: .chore, project: project, displayID: .provisional))
        try env.context.save()
        let continuation = await call(env, ["cursor": cursor])
        let page = try MCPTestHelpers.decodeResult(continuation)
        let secondResults = try #require(page["results"] as? [[String: Any]])
        #expect(secondResults.count == 82)
        #expect(page["nextCursor"] is NSNull)
        #expect(page["expiresAt"] as? String == first["expiresAt"] as? String)
        #expect((firstResults + secondResults).map { $0["description"] as? String } == descriptions)
        let replay = await call(env, ["cursor": cursor])
        #expect(try MCPTestHelpers.errorText(continuation) == MCPTestHelpers.errorText(replay))
    }

    @Test func batchInputPositionsAndDetails() async throws {
        let env = try MCPTestHelpers.makeEnv()
        let project = MCPTestHelpers.makeProject(in: env.context)
        let task = TransitTask(name: "Unallocated", type: .bug, project: project, displayID: .provisional)
        task.metadata = ["branch": "test"]
        env.context.insert(task)
        let rawID = task.id.uuidString.lowercased()
        let page = try MCPTestHelpers.decodeResult(await call(env, [
            "taskIds": [rawID, UUID().uuidString, rawID], "detailLevel": "full",
            "includeComments": false, "limit": 100
        ]))
        let results = try #require(page["results"] as? [[String: Any]])
        #expect(results.map { $0["index"] as? Int } == [0, 1, 2])
        let resolved = try #require(results[0]["task"] as? [String: Any])
        #expect(resolved["description"] is NSNull)
        #expect(resolved["displayId"] == nil)
        #expect(resolved["comments"] == nil)
        #expect(resolved["metadata"] as? [String: String] == ["branch": "test"])
        #expect((results[0]["requested"] as? [String: String])?["taskId"] == rawID)
        #expect((results[1]["error"] as? [String: String])?["code"] == "TASK_NOT_FOUND")
    }

    @Test func paginationInvariants() throws {
        let env = try MCPTestHelpers.makeEnv()
        for count in [0, 1, 99, 100, 101, 182, 500] {
            for limit in [1, 2, 50, 100] {
                env.handler.clearTaskQuerySnapshots()
                let expected = (0..<count).map { ["index": $0] as [String: Any] }
                var text = try env.handler.encodeQueryPages(
                    expected, limit: limit, expiry: Date().addingTimeInterval(300),
                    deadline: ContinuousClock.now.advanced(by: .seconds(300))
                )
                var actual: [Int] = []
                while true {
                    let page = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
                    let results = try #require(page["results"] as? [[String: Int]])
                    #expect(results.count <= limit)
                    actual.append(contentsOf: results.compactMap { $0["index"] })
                    guard let cursor = page["nextCursor"] as? String else { break }
                    text = try env.handler.taskQuerySnapshots.page(for: cursor)
                    #expect(try env.handler.taskQuerySnapshots.page(for: cursor) == text)
                }
                #expect(actual == Array(0..<count))
            }
        }
    }
}
#endif
