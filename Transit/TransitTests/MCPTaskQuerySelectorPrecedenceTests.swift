#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPTaskQuerySelectorPrecedenceTests {
    private struct Failure: Error {}
    private final class FailingProjects: ModelFetching {
        private(set) var calls = 0
        func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) throws -> [T] {
            calls += 1
            throw Failure()
        }
    }

    @Test(arguments: [0, 1, 2])
    func invalidOrBlankProjectSelectorsNeverInvokeStorageHook(mode: Int) async throws {
        let projects = FailingProjects()
        let env = try MCPTestHelpers.makeEnv(projectFetcher: projects)
        var arguments: [String: Any] = ["detailLevel": "summary", "includeComments": false, "limit": 100]
        switch mode {
        case 0: arguments.merge(["projectId": "not-a-uuid", "project": "Alpha"]) { _, new in new }
        case 1: arguments.merge(["projectId": UUID().uuidString, "project": 42]) { _, new in new }
        default: arguments["project"] = " \n\t "
        }
        let response = await env.handler.handle(MCPTestHelpers.toolCallRequest(
            tool: "query_tasks", arguments: arguments))
        #expect(projects.calls == 0)
        if mode == 2 {
            #expect(try !MCPTestHelpers.isError(response))
            #expect(try MCPTestHelpers.decodeQueryResults(response).isEmpty)
        } else {
            let result = try MCPTestHelpers.decodeResult(response)
            #expect((result["error"] as? [String: String])?["code"] == "INVALID_INPUT")
            #expect(try MCPTestHelpers.queryErrorMessage(response) == (mode == 0
                ? "Invalid projectId: expected a UUID string" : "project must be a string"))
        }
    }
}
#endif
