#if os(macOS)
import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MCPBatchTaskSchemaTests {
    private typealias Fixture = MCPBatchTaskRequestFixtures

    @Test func wholeRequestSchemaRequiresExplicitModeAndBoundedClosedItems() throws {
        let schema = try MCPBatchTaskSchema.inputSchema().value
        #expect(Fixture.field("type", in: schema) == .string("object"))
        #expect(Fixture.field("additionalProperties", in: schema) == .boolean(false))
        #expect(try Fixture.names(Fixture.field("required", in: schema)) == ["mode", "items"])
        let properties = Fixture.field("properties", in: schema)
        let mode = Fixture.field("mode", in: properties)
        #expect(Fixture.field("type", in: mode) == .string("string"))
        #expect(try Fixture.names(Fixture.field("enum", in: mode)) == ["dry_run", "execute"])
        let items = Fixture.field("items", in: properties)
        #expect(Fixture.field("type", in: items) == .string("array"))
        #expect(number(Fixture.field("minItems", in: items)) == "1")
        #expect(number(Fixture.field("maxItems", in: items)) == "50")
        #expect(try Fixture.array(Fixture.field("oneOf", in: Fixture.field("items", in: items))).count == 3)
        #expect(Fixture.field("idempotencyKey", in: properties) == nil)
        #expect(Fixture.field("batchId", in: properties) == nil)
    }

    @Test(arguments: ["update_task", "update_task_status", "add_comment"])
    func conditionalOperationBranchesPublishClosedTypedSafetyShapes(operation: String) throws {
        let branch = try branch(operation)
        #expect(Fixture.field("type", in: branch) == .string("object"))
        #expect(Fixture.field("additionalProperties", in: branch) == .boolean(false))
        #expect(try Fixture.names(Fixture.field("required", in: branch)) == ["itemId", "operation", "arguments"])
        let properties = Fixture.field("properties", in: branch)
        let itemId = Fixture.field("itemId", in: properties)
        #expect(Fixture.field("type", in: itemId) == .string("string"))
        #expect(number(Fixture.field("minLength", in: itemId)) == "1")
        #expect(Fixture.field("const", in: Fixture.field("operation", in: properties)) == .string(operation))
        let arguments = Fixture.field("arguments", in: properties)
        #expect(Fixture.field("type", in: arguments) == .string("object"))
        #expect(Fixture.field("additionalProperties", in: arguments) == .boolean(false))
        let required = try Fixture.names(Fixture.field("required", in: arguments))
        #expect(required.contains("taskId") && required.contains("idempotencyKey"))
        let fields = Fixture.field("properties", in: arguments)
        let taskId = Fixture.field("taskId", in: fields)
        #expect(Fixture.field("type", in: taskId) == .string("string"))
        #expect(Fixture.field("format", in: taskId) == .string("uuid"))
        assertExactArguments(operation: operation, fields: fields, required: required)
        #expect(Fixture.field("displayId", in: fields) == nil)
        let key = Fixture.field("idempotencyKey", in: fields)
        #expect(Fixture.field("type", in: key) == .string("string"))
        #expect(Fixture.field("pattern", in: key) == .string("^[A-Za-z0-9._:-]{1,128}$"))
        if operation == "add_comment" {
            #expect(required == ["taskId", "idempotencyKey", "content", "authorName"])
            #expect(Fixture.field("expectedRevision", in: fields) == nil)
        } else {
            #expect(required.contains("expectedRevision"))
            let revision = Fixture.field("expectedRevision", in: fields)
            #expect(Fixture.field("pattern", in: revision) == .string("^r1:[0-9a-f]{64}$"))
            if operation == "update_task_status" {
                #expect(required.contains("status") && !required.contains("authorName"))
            }
        }
    }

    @Test func domainStringsDescribeValuesWithoutWholeShapeEnumOrAuthorConstraints() throws {
        for operation in ["update_task", "update_task_status"] {
            let item = try branch(operation)
            let arguments = Fixture.field("arguments", in: Fixture.field("properties", in: item))
            let fields = Fixture.field("properties", in: arguments)
            for name in operation == "update_task" ? ["type", "priority"] : ["status"] {
                let domain = try #require(Fixture.field(name, in: fields))
                #expect(Fixture.field("type", in: domain) == .string("string"))
                #expect(Fixture.field("enum", in: domain) == nil && Fixture.field("const", in: domain) == nil)
                guard case .string(let description) = Fixture.field("description", in: domain) else {
                    Issue.record("Domain descriptions must explain supported values"); continue
                }
                let allowed: [String]
                switch name {
                case "type": allowed = TaskType.allCases.map(\.rawValue)
                case "priority": allowed = TaskPriority.allCases.map(\.rawValue)
                default: allowed = TaskStatus.allCases.map(\.rawValue)
                }
                #expect(allowed.allSatisfy { description.contains($0) })
            }
            #expect(Fixture.field("if", in: arguments) == nil && Fixture.field("then", in: arguments) == nil)
            #expect(Fixture.field("dependentRequired", in: arguments) == nil)
            if operation == "update_task" {
                let metadata = Fixture.field("metadata", in: fields)
                #expect(Fixture.field("type", in: metadata) == .string("object"))
                let values = Fixture.field("additionalProperties", in: metadata)
                #expect(Fixture.field("type", in: values) == .string("string"))
                #expect(Fixture.field("type", in: Fixture.field("clearMilestone", in: fields)) == .string("boolean"))
                let milestoneId = Fixture.field("milestoneDisplayId", in: fields)
                #expect(Fixture.field("type", in: milestoneId) == .string("integer"))
            }
        }
    }

    private func assertExactArguments(operation: String, fields: MCPJSONValue?, required: Set<String>) {
        let common: Set<String> = ["taskId", "idempotencyKey"]
        let expectedFields: Set<String>
        let expectedRequired: Set<String>
        switch operation {
        case "update_task":
            expectedFields = common.union(["expectedRevision", "name", "description", "type", "priority",
                                           "metadata", "milestone", "milestoneDisplayId", "clearMilestone"])
            expectedRequired = common.union(["expectedRevision"])
        case "update_task_status":
            expectedFields = common.union(["expectedRevision", "status", "comment", "authorName"])
            expectedRequired = common.union(["expectedRevision", "status"])
        default:
            expectedFields = common.union(["content", "authorName"])
            expectedRequired = common.union(["content", "authorName"])
        }
        guard case .object(let members) = fields else {
            Issue.record("Expected exact operation argument properties"); return
        }
        #expect(Set(members.map(\.name)) == expectedFields && required == expectedRequired)
        for field in expectedFields {
            let type = field == "metadata" ? "object" : field == "milestoneDisplayId" ? "integer" :
                field == "clearMilestone" ? "boolean" : "string"
            #expect(Fixture.field("type", in: Fixture.field(field, in: fields)) == .string(type))
        }
    }

    private func branch(_ operation: String) throws -> MCPJSONValue {
        let schema = try MCPBatchTaskSchema.inputSchema().value
        let items = Fixture.field("items", in: Fixture.field("properties", in: schema))
        let choices = try Fixture.array(Fixture.field("oneOf", in: Fixture.field("items", in: items)))
        return try #require(choices.first {
            Fixture.field("const", in: Fixture.field("operation", in: Fixture.field("properties", in: $0))) ==
                .string(operation)
        })
    }

    private func number(_ value: MCPJSONValue?) -> String? {
        guard case .number(let number) = value else { return nil }
        return number.lexeme
    }
}
#endif
