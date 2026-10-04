#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPBatchTaskCoordinatorTests {
    private typealias Fixture = MCPBatchTaskCoordinatorSequenceFixtures

    @Test(arguments: Array(0..<12), ["rejected", "in_progress", "uncertain", "unknown", "malformed", "pending"])
    func seededCallsAreExactCommittedPrefix(seed: Int, kind: String) async throws {
        let count = 1 + seed % 6
        let stopIndex = (seed * 7 + 3) % count
        let request = try Fixture.request(count: count)
        var calls: [Int] = []
        var originals: [Int: MCPResultSource] = [:]
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Fixture.prepared(request), executor: { item in
            calls.append(item.index)
            let source = try Fixture.source(item, kind: item.index == stopIndex ? kind : "committed")
            originals[item.index] = source
            return .init(source: source, pendingEditsStop: item.index == stopIndex && kind == "pending")
        })
        let report = try await batch.run(request)
        #expect(calls == Array(0...stopIndex))
        #expect(report.confirmedCommittedCount == stopIndex)
        #expect(report.summary == (["unknown", "malformed"].contains(kind) ? "evidence_unavailable" : "stopped"))
        let stop = try #require(report.stop)
        #expect(stop.nextUnstartedIndex == stopIndex + 1)
        #expect(stop.blocker == .init(index: stopIndex, itemId: request.items[stopIndex].itemId))
        #expect(stop.reason == (kind == "pending" ? .pendingEdits :
            (["unknown", "malformed"].contains(kind) ? .evidenceUnavailable : .itemResult)))
        #expect(report.isError == true)
        Fixture.assertMappings(report, request: request)
        for entry in report.entries {
            #expect(entry.state == (entry.index <= stopIndex ? .attempted : .notAttempted))
            #expect(entry.originalResult?.originalText == originals[entry.index]?.originalText)
            #expect(entry.originalResult?.originalIsError == originals[entry.index]?.originalIsError)
            #expect(entry.originalResult?.document?.originalUTF8 == originals[entry.index]?.document?.originalUTF8)
            if entry.index > stopIndex { #expect(entry.originalResult == nil) }
        }
    }

    @Test(arguments: Array(0...4))
    func observedCancellationBeforeBetweenAndAfterLast(afterCalls: Int) async throws {
        let request = try Fixture.request()
        var calls: [Int] = []
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Fixture.prepared(request), executor: { item in
            calls.append(item.index)
            return .init(source: try Fixture.source(item))
        }, observedCancellation: { calls.count >= afterCalls })
        let report = try await batch.run(request)
        #expect(calls == Array(0..<afterCalls))
        #expect(report.confirmedCommittedCount == afterCalls)
        #expect(report.observedCancellation)
        #expect(report.summary == (afterCalls == 4 ? "all_committed" : "interrupted"))
        if afterCalls == 4 {
            #expect(report.stop == nil && report.isError == nil)
        } else {
            let stop = try #require(report.stop)
            #expect(stop.reason == .cancelled && stop.nextUnstartedIndex == afterCalls && stop.blocker == nil)
            #expect(report.isError == true)
        }
        Fixture.assertMappings(report, request: request)
    }

    @Test(arguments: ["rejected", "in_progress", "uncertain", "unknown", "malformed", "pending"])
    func unsuccessfulEvidenceWinsCoincidentCancellation(kind: String) async throws {
        let request = try Fixture.request()
        var calls = 0
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Fixture.prepared(request), executor: { item in
            calls += 1
            return .init(source: try Fixture.source(item, kind: kind), pendingEditsStop: kind == "pending")
        }, observedCancellation: { calls > 0 })
        let report = try await batch.run(request)
        #expect(calls == 1 && report.observedCancellation)
        #expect(report.summary == (["unknown", "malformed"].contains(kind) ? "evidence_unavailable" : "stopped"))
        #expect(report.stop?.blocker?.index == 0)
        #expect(report.stop?.reason != .cancelled)
    }

    @Test(arguments: [1, 50])
    func allCommittedRetainsEveryOriginalAndNoError(count: Int) async throws {
        let request = try Fixture.request(count: count)
        var calls: [Int] = []
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Fixture.prepared(request), executor: { item in
            calls.append(item.index)
            return .init(source: try Fixture.source(item))
        })
        let report = try await batch.run(request)
        #expect(calls == Array(0..<count) && report.confirmedCommittedCount == count)
        #expect(report.summary == "all_committed" && report.stop == nil && report.isError == nil)
        #expect(report.entries.allSatisfy { $0.state == .attempted && $0.originalResult != nil })
        Fixture.assertMappings(report, request: request)
    }

    @Test
    func preparedMappingMismatchBlocksEveryDispatch() async throws {
        let request = try Fixture.request(count: 2)
        let other = try Fixture.request(count: 1)
        var calls = 0
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Fixture.prepared(other), executor: { item in
            calls += 1
            return .init(source: try Fixture.source(item))
        })
        do {
            _ = try await batch.run(request)
            Issue.record("Mismatched preencoded recovery mapping must block dispatch")
        } catch let error as MCPBatchTaskCoordinator.Error {
            #expect(error == .preparedRequestMismatch)
        } catch { Issue.record("Unexpected prerequisite error: \(error)") }
        #expect(calls == 0)
    }

    @Test
    func previewModeCannotExecuteEvenWithMatchingCapability() async throws {
        let document = try MCPJSONDocument.parse(JSONSerialization.data(withJSONObject:
            ["mode": "dry_run", "items": [MCPBatchTaskRequestFixtures.item()]]))
        guard case .valid(let request) = try MCPBatchTaskRequest.parse(document) else {
            throw MCPResultBoundaryError.invalidJSON
        }
        var calls = 0
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Fixture.prepared(request), executor: { item in
            calls += 1
            return .init(source: try Fixture.source(item))
        })
        do {
            _ = try await batch.run(request)
            Issue.record("Preview requests must not execute")
        } catch let error as MCPBatchTaskCoordinator.Error {
            #expect(error == .executeModeRequired)
        } catch { Issue.record("Unexpected mode error: \(error)") }
        #expect(calls == 0)
    }

    @Test(arguments: [0, 2])
    func executorFailureAfterInvocationNeverFabricatesNoEffect(index: Int) async throws {
        let request = try Fixture.request()
        var calls: [Int] = []
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Fixture.prepared(request), executor: { item in
            calls.append(item.index)
            if item.index == index { throw MCPBatchTaskCoordinatorFixture.Fault.injected }
            return .init(source: try Fixture.source(item))
        })
        let report = try await batch.run(request)
        #expect(calls == Array(0...index))
        #expect(report.summary == "evidence_unavailable" && report.confirmedCommittedCount == index)
        #expect(report.stop?.reason == .evidenceUnavailable)
        #expect(report.stop?.blocker?.index == index && report.stop?.nextUnstartedIndex == index + 1)
        #expect(report.entries[index].state == .attempted && report.entries[index].originalResult == nil)
        #expect(report.entries[(index + 1)...].allSatisfy { $0.state == .notAttempted })
        #expect(report.isError == true)
        Fixture.assertMappings(report, request: request)
    }

    @Test(arguments: ["committed", "unknown", "malformed"])
    func supplementalPendingHintNeverOverridesSourceEvidence(kind: String) async throws {
        let request = try Fixture.request(count: 1)
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Fixture.prepared(request), executor: { item in
            .init(source: try Fixture.source(item, kind: kind), pendingEditsStop: true)
        })
        let report = try await batch.run(request)
        #expect(report.summary == (kind == "committed" ? "all_committed" : "evidence_unavailable"))
        #expect(report.confirmedCommittedCount == (kind == "committed" ? 1 : 0))
        #expect(report.stop?.reason != .pendingEdits)
    }

    @Test(arguments: ["tool", "key", "uuid"])
    func sameCountDifferentPreparedIdentityBlocksEveryDispatch(field: String) async throws {
        let request = try Fixture.request(count: 1)
        var item = MCPBatchTaskRequestFixtures.item(operation: field == "tool" ? "add_comment" : "update_task")
        var arguments = try #require(item["arguments"] as? [String: Any])
        if field == "key" { arguments["idempotencyKey"] = "different.original.key" }
        if field == "uuid" { arguments["taskId"] = MCPBatchTaskRequestFixtures.taskID(99) }
        item["arguments"] = arguments
        let otherDocument = try MCPBatchTaskRequestFixtures.document(items: [item])
        guard case .valid(let other) = try MCPBatchTaskRequest.parse(otherDocument) else {
            throw MCPResultBoundaryError.invalidJSON
        }
        var calls = 0
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Fixture.prepared(other), executor: { item in
            calls += 1
            return .init(source: try Fixture.source(item))
        })
        do {
            _ = try await batch.run(request)
            Issue.record("Different recovery identity must block dispatch")
        } catch let error as MCPBatchTaskCoordinator.Error {
            #expect(error == .preparedRequestMismatch)
        } catch { Issue.record("Unexpected identity prerequisite error: \(error)") }
        #expect(calls == 0)
    }

    @Test(arguments: ["reason", "blank", "missingEvidence"])
    func mixedOperationSourceRequiresStatusReasonOnlyWhenNonblank(scenario: String) async throws {
        var status = MCPBatchTaskRequestFixtures.item(1, operation: "update_task_status")
        var arguments = try #require(status["arguments"] as? [String: Any])
        arguments["comment"] = scenario == "blank" ? " \n" : " Reason "
        arguments["authorName"] = "Agent"
        status["arguments"] = arguments
        let values = [MCPBatchTaskRequestFixtures.item(0), status,
                      MCPBatchTaskRequestFixtures.item(2, operation: "add_comment")]
        let document = try MCPBatchTaskRequestFixtures.document(items: values)
        guard case .valid(let request) = try MCPBatchTaskRequest.parse(document) else {
            throw MCPResultBoundaryError.invalidJSON
        }
        var calls: [String] = []
        let batch = MCPBatchTaskCoordinator(preparedResponse: try Fixture.prepared(request), executor: { item in
            calls.append(item.operation)
            let kind = item.index == 1 && scenario != "reason" ? "missingStatusComment" : "committed"
            return .init(source: try Fixture.source(item, kind: kind))
        })
        let report = try await batch.run(request)
        #expect(calls == (scenario == "missingEvidence" ? ["update_task", "update_task_status"] :
            ["update_task", "update_task_status", "add_comment"]))
        #expect(report.summary == (scenario == "missingEvidence" ? "evidence_unavailable" : "all_committed"))
        #expect(report.confirmedCommittedCount == (scenario == "missingEvidence" ? 1 : 3))
    }
}
#endif
