#if os(macOS)
import Foundation
import SwiftData
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TaskLinkWireTests {
    let source = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let target = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    let revision = "r1:" + String(repeating: "a", count: 64)
    let occurrenceRevision = "l1:" + String(repeating: "b", count: 64)

    func arguments(changes: [[String: Any]]) -> [String: Any] {
        ["taskId": source.uuidString, "expectedRevision": revision, "idempotencyKey": "wire",
         "linkChanges": changes, "endpointPreconditions": []]
    }

    func addition(_ type: String = "blocks", target: UUID? = nil) -> [String: Any] {
        ["action": "add", "type": type, "targetTaskId": (target ?? self.target).uuidString]
    }

    @Test(arguments: TaskLinkType.allCases)
    func exactPublicTypesReachAcceptedCommandShape(type: TaskLinkType) throws {
        let command = try MCPWriteCommand.validate(
            tool: "update_task", arguments: arguments(changes: [addition(type.rawValue)]))
        #expect(command.tool == "update_task")
    }

    @Test(arguments: [0, 50])
    func directiveBoundaryIsInclusive(count: Int) throws {
        let changes = (0..<count).map { _ in addition(target: UUID()) }
        _ = try MCPWriteCommand.validate(tool: "update_task", arguments: arguments(changes: changes))
    }

    @Test func omittedLinkFieldsPreserveOrdinaryCommandShape() throws {
        var args = arguments(changes: [])
        args.removeValue(forKey: "linkChanges")
        args.removeValue(forKey: "endpointPreconditions")
        args["name"] = "ordinary update"
        _ = try MCPWriteCommand.validate(tool: "update_task", arguments: args)
    }

    @Test(arguments: ["unknownType", "badUUID", "badL1", "duplicateRemove", "extraField", "sourcePrecondition",
                      "duplicateEndpoint", "oversize", "removeOnCreate", "self", "duplicateAddition"])
    // Each row isolates one closed-shape rejection through the actual command parser.
    // swiftlint:disable:next cyclomatic_complexity
    func malformedDeltaRejectsBeforeDomainLookup(fault: String) throws {
        var args = arguments(changes: [addition()])
        var tool = "update_task"
        switch fault {
        case "unknownType": args["linkChanges"] = [addition("blocked_by")]
        case "badUUID": args["linkChanges"] = [["action": "add", "type": "blocks", "targetTaskId": "T-42"]]
        case "badL1": args["linkChanges"] = [["action": "remove", "edgeId": target.uuidString,
                                              "occurrenceRevision": revision]]
        case "duplicateRemove":
            let remove: [String: Any] = ["action": "remove", "edgeId": target.uuidString,
                                         "occurrenceRevision": occurrenceRevision]
            args["linkChanges"] = [remove, remove]
        case "extraField": var add = addition(); add["displayId"] = 42; args["linkChanges"] = [add]
        case "sourcePrecondition":
            args["endpointPreconditions"] = [["taskId": source.uuidString, "expectedRevision": revision]]
        case "duplicateEndpoint":
            let guardValue = ["taskId": target.uuidString, "expectedRevision": revision]
            args["endpointPreconditions"] = [guardValue, guardValue]
        case "oversize": args["linkChanges"] = (0..<51).map { _ in addition(target: UUID()) }
        case "removeOnCreate":
            tool = "create_task"
            args = ["name": "created", "type": "feature", "projectId": source.uuidString, "idempotencyKey": "wire",
                    "linkChanges": [["action": "remove", "edgeId": target.uuidString,
                                      "occurrenceRevision": occurrenceRevision]]]
        case "self": args["linkChanges"] = [addition(target: source)]
        default: args["linkChanges"] = [addition("relates-to"), addition("relates-to")]
        }
        #expect(throws: MCPWriteFailure.self) { try MCPWriteCommand.validate(tool: tool, arguments: args) }
    }

    @Test(arguments: ["add", "remove"])
    func validShapeDoesNotPerformMissingReferenceOrSelectorLookup(action: String) throws {
        let change = action == "add" ? addition() : ["action": "remove", "edgeId": target.uuidString,
                                                     "occurrenceRevision": occurrenceRevision]
        _ = try MCPWriteCommand.validate(tool: "update_task", arguments: arguments(changes: [change]))
    }

    @Test(arguments: ["linkChanges", "endpointPreconditions"])
    func batchRejectsGraphFieldsBeforeAnyItemAcceptance(field: String) throws {
        var args: [String: Any] = ["taskId": source.uuidString, "expectedRevision": revision, "idempotencyKey": "wire"]
        args[field] = [] as [String]
        let request = try MCPBatchTaskRequestFixtures.document(mode: "execute", items: [
            ["itemId": "one", "operation": "update_task", "arguments": args]
        ])
        #expect(throws: (any Error).self) { try MCPBatchTaskRequestFixtures.valid(request) }
    }

    @Test func freshLinkRequestCannotBeAcceptedWithoutOwnedPolicy() async throws {
        let fixture = try TaskLinkCommitDiskFixture()
        var args = try fixture.updateArguments()
        args["linkChanges"] = [addition("relates-to", target: fixture.target.id)]
        args["endpointPreconditions"] = [["taskId": fixture.target.id.uuidString,
            "expectedRevision": try MCPRecordSnapshot.task(fixture.target, in: fixture.owner.context).revision]]
        let result = try fixture.decode(await fixture.coordinator(save: { context, _ in try context.save() })
            .execute(tool: "update_task", arguments: args))
        #expect(result["accepted"] as? Bool == false)
        let error = try #require(result["error"] as? [String: Any])
        #expect(error["code"] as? String == "PERSISTENCE_UNAVAILABLE")
        #expect(try fixture.receipts(in: fixture.owner.context).isEmpty)
    }

    @Test func taskSchemasDescribeLinkGuardsAndUnsupportedBatches() throws {
        for name in ["create_task", "update_task"] {
            let definition = try #require(MCPToolDefinitions.coreTools.first { $0.name == name })
            #expect(definition.inputSchema.properties?["linkChanges"]?.type == "array")
            #expect(definition.inputSchema.properties?["endpointPreconditions"]?.type == "array")
            #expect(definition.description.contains("50"))
            #expect(definition.description.contains("seven days"))
            #expect(definition.description.contains("batch"))
        }
    }
}
#endif
