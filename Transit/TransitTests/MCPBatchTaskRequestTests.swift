#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPBatchTaskRequestTests {
    private typealias Fixture = MCPBatchTaskRequestFixtures

    @Test(arguments: [0, 1, 50, 51])
    func itemCountBoundsApplyBeforeAdmission(count: Int) throws {
        let document = try Fixture.document(items: (0..<count).map { Fixture.item($0) })
        if (1...50).contains(count) {
            let request = try Fixture.valid(document)
            #expect(request.items.count == count && request.mode == .execute)
            #expect(request.items.map(\.index) == Array(0..<count))
        } else { try Fixture.invalid(document, field: "items") }
    }

    @Test(arguments: ["execute", "dry_run", "Execute", "dry-run", "", "number", "boolean", "null"])
    func explicitModeUsesExactStringValues(mode: String) throws {
        let value: Any
        switch mode {
        case "number": value = 1
        case "boolean": value = true
        case "null": value = NSNull()
        default: value = mode
        }
        let document = try Fixture.document(mode: value, items: [Fixture.item()])
        if mode == "execute" || mode == "dry_run" {
            #expect(try Fixture.valid(document).mode.rawValue == mode)
        } else { try Fixture.invalid(document, field: "mode") }
    }

    @Test(arguments: ["update_task", "update_task_status", "add_comment", "create_task", "UPDATE_TASK"])
    func onlyExplicitProtectedTaskOperationsAreAdmitted(operation: String) throws {
        let document = try Fixture.document(items: [Fixture.item(operation: operation)])
        if ["update_task", "update_task_status", "add_comment"].contains(operation) {
            let item = try #require(Fixture.valid(document).items.first)
            #expect(item.operation == operation && item.command.tool == operation)
        } else { try Fixture.invalid(document, index: 0, itemId: "caller.0", field: "operation") }
    }

    @Test(arguments: ["missingMode", "missingItems", "outerKey", "correlation", "itemsObject",
                      "itemsNull", "outerArray", "outerBoolean"])
    func outerMissingUnknownAndWrongTypesRejectWholeShape(kind: String) throws {
        var root: [String: Any] = ["mode": "execute", "items": [Fixture.item()]]
        switch kind {
        case "missingMode": root.removeValue(forKey: "mode")
        case "missingItems": root.removeValue(forKey: "items")
        case "outerKey": root["idempotencyKey"] = "outer.forbidden"
        case "correlation": root["batchId"] = "unsupported"
        case "itemsObject": root["items"] = ["0": Fixture.item()]
        case "itemsNull": root["items"] = NSNull()
        default: break
        }
        let value: Any
        switch kind {
        case "outerArray": value = [root]
        case "outerBoolean": value = true
        default: value = root
        }
        try Fixture.invalid(Fixture.document(value))
    }

    @Test(arguments: ["missingID", "missingOperation", "missingArguments", "extra", "idBoolean",
                      "idNumber", "idEmpty", "idBlank", "operationNumber", "argumentsArray", "argumentsNull",
                      "argumentsScalar",
                      "itemNull"])
    func itemShapeDiagnosticsRetainUsableCallerMapping(kind: String) throws {
        var item = Fixture.item()
        let mutations: [String: (String, Any?)] = [
            "missingID": ("itemId", nil), "missingOperation": ("operation", nil),
            "missingArguments": ("arguments", nil), "extra": ("retry", true),
            "idBoolean": ("itemId", true), "idNumber": ("itemId", 1), "idEmpty": ("itemId", ""),
            "idBlank": ("itemId", " \n\t "), "operationNumber": ("operation", 1),
            "argumentsArray": ("arguments", [] as [String]), "argumentsNull": ("arguments", NSNull()),
            "argumentsScalar": ("arguments", "arguments")
        ]
        if let (field, value) = mutations[kind] { item[field] = value }
        if kind == "itemNull" {
            try Fixture.invalid(Fixture.document(["mode": "execute", "items": [NSNull()]]), index: 0)
        } else {
            let usable = ["missingOperation", "missingArguments", "extra", "operationNumber", "argumentsArray",
                          "argumentsNull", "argumentsScalar"]
            try Fixture.invalid(Fixture.document(items: [item]), index: 0,
                                itemId: usable.contains(kind) ? "caller.0" : nil)
        }
    }

    @Test(arguments: ["missingTask", "displayID", "invalidUUID", "taskNull", "taskNumber",
                      "missingKey", "blankKey", "unicodeKey", "longKey", "keyNull", "keyBoolean", "keyNewline",
                      "keyTrailingNewline",
                      "missingRevision", "badRevision", "upperRevision", "revisionNumber", "revisionNewline",
                      "statusMissing", "contentMissing", "commentAuthorMissing", "commentRevision", "unknownArgument"])
    func requiredSafetyAndOperationFieldsRejectBeforeAnyItem(kind: String) throws {
        let operation = kind.hasPrefix("comment") || kind == "contentMissing" ? "add_comment" :
            kind == "statusMissing" ? "update_task_status" : "update_task"
        var item = Fixture.item(1, operation: operation)
        var arguments = try #require(item["arguments"] as? [String: Any])
        let mutations: [String: (String, Any?)] = [
            "missingTask": ("taskId", nil), "displayID": ("displayId", 42), "invalidUUID": ("taskId", "T-42"),
            "taskNull": ("taskId", NSNull()), "taskNumber": ("taskId", 42),
            "missingKey": ("idempotencyKey", nil), "blankKey": ("idempotencyKey", ""),
            "unicodeKey": ("idempotencyKey", "key.é"),
            "longKey": ("idempotencyKey", String(repeating: "k", count: 129)),
            "keyNull": ("idempotencyKey", NSNull()), "keyBoolean": ("idempotencyKey", true),
            "keyNewline": ("idempotencyKey", "key\ninside"), "keyTrailingNewline": ("idempotencyKey", "key\n"),
            "missingRevision": ("expectedRevision", nil),
            "badRevision": ("expectedRevision", "r1:" + String(repeating: "a", count: 63)),
            "upperRevision": ("expectedRevision", Fixture.revision.uppercased()),
            "revisionNumber": ("expectedRevision", 1), "revisionNewline": ("expectedRevision", Fixture.revision + "\n"),
            "statusMissing": ("status", nil), "contentMissing": ("content", nil),
            "commentAuthorMissing": ("authorName", nil), "commentRevision": ("expectedRevision", Fixture.revision),
            "unknownArgument": ("unsupported", "value")
        ]
        let (field, value) = try #require(mutations[kind])
        arguments[field] = value
        item["arguments"] = arguments
        try Fixture.invalid(Fixture.document(items: [Fixture.item(), item]), index: 1, itemId: "caller.1", field: field)
    }

    @Test(arguments: ["nameBoolean", "descriptionNull", "typeNumber", "priorityArray", "statusBoolean",
                      "commentObject", "authorNumber", "contentBoolean", "milestoneBoolean", "integerBoolean",
                      "integerFraction", "integerString", "boolNumber", "boolString", "metadataArray", "metadataNumber",
                      "metadataBoolean", "metadataNull"])
    func actualJSONTypesDoNotCoerceBooleansNumbersOrMetadata(kind: String) throws {
        let operation = kind == "contentBoolean" ? "add_comment" :
            ["statusBoolean", "commentObject", "authorNumber"].contains(kind) ? "update_task_status" : "update_task"
        var item = Fixture.item(operation: operation)
        var arguments = try #require(item["arguments"] as? [String: Any])
        let mutations: [String: (String, Any)] = [
            "nameBoolean": ("name", true), "descriptionNull": ("description", NSNull()),
            "typeNumber": ("type", 1), "priorityArray": ("priority", ["high"]), "statusBoolean": ("status", true),
            "commentObject": ("comment", ["content": "reason"]), "authorNumber": ("authorName", 1),
            "contentBoolean": ("content", true), "milestoneBoolean": ("milestone", false),
            "integerBoolean": ("milestoneDisplayId", true), "integerFraction": ("milestoneDisplayId", 1.5),
            "integerString": ("milestoneDisplayId", "1"), "boolNumber": ("clearMilestone", 1),
            "boolString": ("clearMilestone", "true"), "metadataArray": ("metadata", ["tag"]),
            "metadataBoolean": ("metadata", ["tag": true]), "metadataNull": ("metadata", ["tag": NSNull()]),
            "metadataNumber": ("metadata", ["tag": 1])
        ]
        let (field, value) = try #require(mutations[kind])
        arguments[field] = value
        item["arguments"] = arguments
        try Fixture.invalid(Fixture.document(items: [item]), index: 0, itemId: "caller.0", field: field)
    }

}

@MainActor extension MCPBatchTaskRequestTests {
    @Test(arguments: ["boolean", "integer", "equivalentInteger", "metadata", "keyBoundary"])
    func validTypedArgumentsRemainUnnormalizedForOriginalBinding(kind: String) throws {
        var item = Fixture.item()
        var arguments = try #require(item["arguments"] as? [String: Any])
        switch kind {
        case "boolean": arguments["clearMilestone"] = false
        case "integer", "equivalentInteger": arguments["milestoneDisplayId"] = 1
        case "metadata": arguments["metadata"] = ["tag": " Original value "]
        default: arguments["idempotencyKey"] = String(repeating: "a", count: 128)
        }
        arguments["taskId"] = Fixture.taskID(0).lowercased()
        arguments["description"] = " Original e\u{0301} description "
        item["arguments"] = arguments
        var document = try Fixture.document(items: [item])
        if kind == "equivalentInteger" {
            let text = try #require(String(data: document.originalUTF8, encoding: .utf8))
            let replaced = text.replacingOccurrences(of: "\"milestoneDisplayId\":1",
                                                      with: "\"milestoneDisplayId\":1.0")
            #expect(replaced != text)
            document = try MCPJSONDocument.parse(replaced)
        }
        let parsed = try #require(Fixture.valid(document).items.first)
        for field in ["taskId", "name", "description"] {
            let original = try #require(arguments[field] as? String)
            let retained = try #require(parsed.command.arguments[field] as? String)
            #expect(retained.utf8.elementsEqual(original.utf8))
        }
        if kind == "equivalentInteger" {
            guard case .number(let value) = Fixture.field("milestoneDisplayId", in: parsed.originalArguments) else {
                Issue.record("Expected original exact numeric lexeme"); return
            }
            #expect(value.lexeme == "1.0")
        }
        #expect(parsed.targetTaskId == UUID(uuidString: Fixture.taskID(0)))
        let logicalItems = try Fixture.array(Fixture.field("items", in: document.value))
        #expect(parsed.originalArguments == Fixture.field("arguments", in: logicalItems.first))
        #expect(try MCPCanonicalJSON.encode(parsed.command.arguments) == MCPCanonicalJSON.encode(arguments))
    }

    @Test func updateWithOnlyRequiredSafetyFieldsRemainsAValidNoOpShape() throws {
        var item = Fixture.item()
        var arguments = try #require(item["arguments"] as? [String: Any])
        arguments.removeValue(forKey: "name")
        item["arguments"] = arguments
        let parsed = try #require(Fixture.valid(Fixture.document(items: [item])).items.first)
        #expect(Set(parsed.command.arguments.keys) == ["taskId", "expectedRevision", "idempotencyKey"])
        #expect(try MCPCanonicalJSON.encode(parsed.command.arguments) == MCPCanonicalJSON.encode(arguments))
    }

    @Test(arguments: ["status", "type", "priority", "statusEmpty", "typeEmpty", "priorityEmpty", "statusCommentAuthor"])
    func domainStringsAndConditionalAuthorStayOutsideWholeShapeValidation(kind: String) throws {
        let operation = kind.hasPrefix("status") ? "update_task_status" : "update_task"
        var item = Fixture.item(operation: operation)
        var arguments = try #require(item["arguments"] as? [String: Any])
        if kind == "statusCommentAuthor" {
            arguments["comment"] = "Reason"
        } else if kind.hasSuffix("Empty") {
            arguments[String(kind.dropLast(5))] = ""
        } else { arguments[kind] = "not-a-domain-value" }
        item["arguments"] = arguments
        let parsed = try #require(Fixture.valid(Fixture.document(items: [item])).items.first)
        #expect(parsed.command.tool == operation)
        #expect(try MCPCanonicalJSON.encode(parsed.command.arguments) == MCPCanonicalJSON.encode(arguments))
    }

    @Test(arguments: ["itemId", "taskAlias", "toolKey", "sameTaskDifferentOperation"])
    func collisionNamespacesAreDistinctAndCheckedOverTheWholeRequest(kind: String) throws {
        var first = Fixture.item()
        var second = Fixture.item(1)
        var arguments = try #require(second["arguments"] as? [String: Any])
        switch kind {
        case "itemId": second["itemId"] = first["itemId"]
        case "taskAlias": arguments["taskId"] = Fixture.taskID(0).uppercased()
        case "toolKey": arguments["idempotencyKey"] = "batch.key.0"
        default:
            first = Fixture.item(operation: "add_comment")
            arguments["taskId"] = Fixture.taskID(0)
        }
        second["arguments"] = arguments
        try Fixture.invalid(Fixture.document(items: [first, second]), index: 1, itemId: second["itemId"] as? String)
    }

    @Test(arguments: ["case", "unicode", "sameKeyDifferentTool"])
    func opaqueCallerIDsAndToolScopedKeysDoNotAcquireExtraNormalization(kind: String) throws {
        var first = Fixture.item()
        var second = Fixture.item(1, operation: kind == "sameKeyDifferentTool" ? "add_comment" : "update_task")
        if kind == "unicode" {
            first["itemId"] = "é"; second["itemId"] = "e\u{0301}"
        } else { first["itemId"] = "Caller"; second["itemId"] = "caller" }
        if kind == "sameKeyDifferentTool" {
            var arguments = try #require(second["arguments"] as? [String: Any])
            arguments["idempotencyKey"] = "batch.key.0"
            second["arguments"] = arguments
        }
        let parsed = try Fixture.valid(Fixture.document(items: [first, second]))
        #expect(parsed.items.count == 2)
        #expect(parsed.items[0].itemId.unicodeScalars.elementsEqual((first["itemId"] as? String ?? "").unicodeScalars))
        #expect(parsed.items[1].itemId.unicodeScalars.elementsEqual((second["itemId"] as? String ?? "").unicodeScalars))
    }

    @Test(arguments: [UInt64(1), 7, 41, 2_384])
    func seededPermutationsPreserveInputOrderAndRejectInjectedCollisions(seed: UInt64) throws {
        let shuffled = Fixture.permuted((0..<12).map { Fixture.item($0) }, seed: seed)
        let request = try Fixture.valid(Fixture.document(items: shuffled))
        #expect(request.items.map(\.itemId) == shuffled.compactMap { $0["itemId"] as? String })
        #expect(request.items.map(\.index) == Array(0..<12))
        for collision in ["itemId", "taskId", "idempotencyKey"] {
            var items = shuffled
            if collision == "itemId" { items[11][collision] = items[0][collision] } else {
                var last = try #require(items[11]["arguments"] as? [String: Any])
                let first = try #require(items[0]["arguments"] as? [String: Any])
                last[collision] = first[collision]
                items[11]["arguments"] = last
            }
            try Fixture.invalid(Fixture.document(items: items), index: 11, itemId: items[11]["itemId"] as? String)
        }
    }

    @Test func invalidLastItemPreventsAdmissionOfEveryEarlierValidItem() throws {
        var invalid = Fixture.item(2)
        invalid["arguments"] = ["taskId": Fixture.taskID(2)]
        let document = try Fixture.document(items: [Fixture.item(), Fixture.item(1), invalid])
        var admissions = 0
        switch try MCPBatchTaskRequest.parse(document) {
        case .valid(let request): admissions += request.items.count
        case .invalid(let diagnostics): #expect(diagnostics.contains { $0.index == 2 && $0.itemId == "caller.2" })
        }
        #expect(admissions == 0)
    }
}
#endif
