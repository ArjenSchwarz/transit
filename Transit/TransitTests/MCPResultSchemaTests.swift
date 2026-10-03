#if os(macOS)
import Foundation
import Testing
@testable import Transit

/// Export is app-test-owned. The host validator reads it only after the runner exits.
@MainActor
@Suite(.serialized)
struct MCPResultSchemaTests {
    @Test func descriptorsAdvertiseSelfContainedDraft202012() throws {
        let descriptor = try MCPResultSchemas.descriptor(tool: "query_tasks", description: "Schema fixture")
        #expect(descriptor.tool == "query_tasks")
        #expect(!descriptor.description.isEmpty)
        #expect(MCPResultEncoderFixtures.field("$schema", in: descriptor.outputSchema.value)
            == .string("https://json-schema.org/draft/2020-12/schema"))
    }

    @Test func exportActualStructuredSourceAndPresentationCorpus() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("transit-mcp-schema-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        print("TRANSIT_MCP_SCHEMA_EXPORT=" + directory.path)
        var fixtures = try Self.exportSources(to: directory)
        fixtures += try Self.exportCategories(to: directory)
        let names = ["query_tasks", "get_projects", "query_milestones", "create_task", "update_task",
                     "update_task_status", "add_comment", "create_project", "create_milestone",
                     "update_milestone", "delete_milestone", "synthetic_mutate_tasks"]
        var manifest: [String: Any] = ["exportVersion": 1, "status": "incomplete",
            "fixtures": fixtures, "schemas": [], "negativeCases": Self.negativeCases]
        let manifestURL = directory.appendingPathComponent("manifest.json")
        try Self.writeManifest(manifest, to: manifestURL)
        do {
            var schemas: [[String: String]] = []
            for name in names {
                let descriptor = try MCPResultSchemas.descriptor(tool: name, description: "Synthetic schema consumer")
                let filename = name + "-schema.json"
                try descriptor.outputSchema.originalUTF8.write(to: directory.appendingPathComponent(filename))
                schemas.append(["tool": name, "file": filename])
            }
            manifest["schemas"] = schemas
            manifest["status"] = "complete"
            try Self.writeManifest(manifest, to: manifestURL)
        } catch {
            manifest["failure"] = String(describing: error)
            try Self.writeManifest(manifest, to: manifestURL)
            throw error // Expected RED is the real descriptor boundary, not missing test types.
        }
    }

    private static func exportSources(to directory: URL) throws -> [[String: Any]] {
        var fixtures: [[String: Any]] = []
        for sample in Self.samples {
            let source = try MCPResultAdapter.source(text: sample.text, isError: sample.isError,
                origin: sample.origin, evidence: sample.evidence)
            let presentation = try MCPResultAdapter.present(source, context: Self.context(sample))
            if sample.name == "escaped_pointer" {
                #expect(presentation.links.count == 1)
                let link = try #require(presentation.links.first)
                #expect(link.sourcePath == "/records~1group/records~0group")
                #expect(link.entityId.uuidString == "AA000000-0000-0000-0000-000000000001")
            }
            if sample.name == "linked_record" { #expect(presentation.links.count == 2) }
            let bytes = try MCPResultEncoder.encode(source: source, presentation: presentation,
                id: .string(sample.name), metadata: nil)
            try bytes.write(to: directory.appendingPathComponent(sample.name + ".json"), options: .atomic)
            let result = try MCPResultEncoderFixtures.result(bytes, id: .string(sample.name))
            #expect(try MCPResultEncoderFixtures.originalText(result) == sample.text)
            #expect(MCPResultEncoderFixtures.field("isError", in: result)
                == sample.isError.map { .boolean($0) })
            fixtures.append(["name": sample.name, "file": sample.name + ".json"])
        }
        let fallbackSource = try MCPResultAdapter.source(
            text: #"{"summary":"serialization_failed","effectEvidence":"unestablished"}"#,
            isError: true, origin: .generatedJSON, evidence: .unestablished)
        let batchSample = try #require(Self.samples.first { $0.name == "batch" })
        let fallback = try MCPResultEncoder.prepareMutationFallback(
            id: .string("batch_fallback"), source: fallbackSource,
            context: Self.context(batchSample), metadata: nil)
        try fallback.write(to: directory.appendingPathComponent("batch_fallback.json"))
        fixtures.append(["name": "batch_fallback", "file": "batch_fallback.json"])
        return fixtures
    }

    private static func exportCategories(to directory: URL) throws -> [[String: Any]] {
        var fixtures: [[String: Any]] = []
        for category in Self.categories {
            let source = try MCPResultAdapter.source(text: "{}", isError: true,
                origin: .generatedJSON, evidence: .established)
            let context = MCPResultContext(tool: "query_tasks",
                semanticFailure: MCPResultFailure(category: category, diagnostic: nil),
                mutationRecovery: nil, entityPositions: [])
            let presentation = try MCPResultAdapter.present(source, context: context)
            #expect(presentation.errorCategory == category)
            let name = "category_" + category.rawValue
            let bytes = try MCPResultEncoder.encode(source: source, presentation: presentation,
                id: .string(name), metadata: nil)
            try bytes.write(to: directory.appendingPathComponent(name + ".json"))
            fixtures.append(["name": name, "file": name + ".json"])
        }
        return fixtures
    }

    private static func writeManifest(_ value: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: url, options: .atomic)
    }

    private struct Sample {
        let name: String
        let text: String
        var isError: Bool?
        var origin: MCPResultOrigin = .generatedJSON
        var evidence: MCPResultEvidence = .established
    }

    private static let samples: [Sample] = [
        Sample(name: "object", text: "{}"),
        Sample(name: "array", text: "[{},null,false,1,\"saved\"]", isError: false),
        Sample(name: "null", text: "null"),
        Sample(name: "boolean", text: "false"),
        Sample(name: "string", text: "\"\""),
        Sample(name: "number", text: "1E-9999"),
        Sample(name: "huge_number", text: "99999999999999999999999999999999999999999999999999"),
        Sample(name: "historical", text: #"""
            {"contractVersion":99,"source":null,"presentation":false,"é":1,"é":2,
            "unknown":{"absentSibling":null,"flag":false,"decimal":1.234567890123456789,
            "exponent":1E9999},"outcome":"future","retryAction":null}
            """#,
               isError: false, origin: .retainedJSON, evidence: .unestablished),
        Sample(name: "retained_error", text: #"""
            {"code":"FUTURE_ERROR","message":"saved","accepted":true,"unknown":null}
            """#,
               isError: true, origin: .retainedJSON, evidence: .unestablished),
        Sample(name: "text", text: "Invalid input\n", isError: true, origin: .plainText),
        Sample(name: "empty_text", text: "", origin: .plainText),
        Sample(name: "unreadable", text: "{broken saved evidence", isError: true, origin: .retainedJSON),
        Sample(name: "retry_read", text: #"{"error":{"code":"READ_TIMEOUT"}}"#, isError: true),
        Sample(name: "restart_read", text: #"{"error":{"code":"QUERY_EXPIRED"}}"#, isError: true),
        Sample(name: "maintenance", text: "maintenance original evidence", isError: true,
               origin: .plainText, evidence: .unestablished),
        Sample(name: "follow_source", text: #"""
            {"contractVersion":1,"outcome":"rejected","accepted":false,
            "retryAction":"new_request_new_key","error":{"code":"INVALID_INPUT"}}
            """#,
               isError: true, origin: .retainedJSON),
        Sample(name: "linked_record", text: #"""
            {"record":{"taskId":"AA000000-0000-0000-0000-000000000001",
            "projectId":"BB000000-0000-0000-0000-000000000002","revision":"r1:saved","unknown":false}}
            """#),
        Sample(name: "escaped_pointer",
               text: #"{"records/group":{"records~group":"AA000000-0000-0000-0000-000000000001"}}"#),
        Sample(name: "batch", text: #"""
            {"contractVersion":1,"mode":"execute","atomicity":"per_item","summary":"stopped",
            "items":[{"index":0,"originalResult":{"logicalJSON":{"contractVersion":99,
            "outcome":"future","unknown":null},"text":" original saved bytes ","isError":false}},
            {"index":1,"originalResult":{"logicalJSON":null,"text":"null"}},{"index":2,
            "originalResult":{"logicalJSON":false,"text":"false","isError":null}},{"index":3,
            "originalResult":{"logicalJSON":{"error":"saved"},"text":"saved error","isError":true}}]}
            """#,
               isError: true, evidence: .unestablished)
    ]

    private static func context(_ sample: Sample) -> MCPResultContext {
        var positions: [MCPResultEntityPosition] = []
        var mutation: MCPMutationRecoveryContext?
        if sample.name == "linked_record" {
            positions = [MCPResultEntityPosition(entityType: .task, sourcePath: "/record"),
                         MCPResultEntityPosition(entityType: .project, sourcePath: "/record/projectId")]
        }
        if sample.name == "escaped_pointer" {
            positions = [MCPResultEntityPosition(entityType: .task, sourcePath: "/records~1group/records~0group")]
        }
        if ["unreadable", "historical", "retained_error", "follow_source"].contains(sample.name) {
            mutation = .protectedWrite(MCPProtectedRecoveryKey(tool: "update_task", idempotencyKey: "original-key"))
        }
        if sample.name == "maintenance" { mutation = .unprotectedMaintenance(tool: "maintenance_fixture") }
        if sample.name == "batch" {
            mutation = .applicationBatch(items: [MCPBatchRecoveryItem(
                index: 0, itemId: "first", operation: "update_task",
                originalKey: MCPProtectedRecoveryKey(tool: "update_task", idempotencyKey: "original-batch-key"),
                targetTaskId: UUID(uuidString: "AA000000-0000-0000-0000-000000000001"))])
        }
        return MCPResultContext(tool: sample.name == "linked_record" ? "update_task" : "fixture",
            semanticFailure: nil, mutationRecovery: mutation, entityPositions: positions)
    }

    /// Host-only mutations start from actual emitted structuredContent, never a golden descriptor.
    private static let negativeCases: [[String: Any]] = [
        invalid("missing_version", "object", ["contractVersion"], remove: true),
        invalid("wrong_version", "object", ["contractVersion"], value: 2),
        invalid("boolean_version", "object", ["contractVersion"], value: true),
        invalid("missing_source", "object", ["source"], remove: true),
        invalid("missing_presentation", "object", ["presentation"], remove: true),
        invalid("unknown_kind", "object", ["source", "kind"], value: "future"),
        invalid("missing_kind", "object", ["source", "kind"], remove: true),
        invalid("json_missing_payload", "object", ["source", "payload"], remove: true),
        invalid("text_missing_payload", "text", ["source", "payload"], remove: true),
        invalid("text_nonstring_payload", "text", ["source", "payload"], value: NSNull()),
        invalid("unreadable_payload", "unreadable", ["source", "payload"], value: NSNull()),
        invalid("unreadable_established", "unreadable", ["presentation", "evidence"], value: "established"),
        invalid("missing_evidence", "object", ["presentation", "evidence"], remove: true),
        invalid("invalid_evidence", "object", ["presentation", "evidence"], value: "future"),
        invalid("missing_links", "object", ["presentation", "links"], remove: true),
        invalid("links_nonarray", "object", ["presentation", "links"], value: NSNull()),
        invalid("invalid_category", "object", ["presentation", "errorCategory"], value: "future"),
        invalid("category_null", "object", ["presentation", "errorCategory"], value: NSNull()),
        invalid("invalid_recovery", "object", ["presentation", "recovery"], value: ["direction": "fresh_key"]),
        invalid("recovery_missing_direction", "object", ["presentation", "recovery"], value: [String: String]()),
        invalid("recovery_invalid_tool", "unreadable", ["presentation", "recovery", "tool"], value: false),
        invalid("recovery_invalid_key", "unreadable", ["presentation", "recovery", "idempotencyKey"], value: NSNull()),
        invalid("invalid_entity", "linked_record", ["presentation", "links", "0", "entityType"], value: "milestone"),
        invalid("invalid_uuid", "linked_record", ["presentation", "links", "0", "entityId"], value: "T-1"),
        invalid("invalid_pointer", "linked_record", ["presentation", "links", "0", "sourcePath"], value: "record"),
        invalid("invalid_pointer_escape", "linked_record", ["presentation", "links", "0", "sourcePath"],
                value: "/record~2name"),
        invalid("guessed_available", "linked_record", ["presentation", "links", "0", "availability"],
                value: "available"),
        invalid("guessed_uri", "linked_record", ["presentation", "links", "0", "uri"], value: "transit://task/1"),
        invalid("missing_link_reason", "linked_record", ["presentation", "links", "0", "reason"], remove: true),
        invalid("wrong_link_reason", "linked_record", ["presentation", "links", "0", "reason"], value: "guess"),
        invalid("missing_entity_id", "linked_record", ["presentation", "links", "0", "entityId"], remove: true),
        invalid("missing_entity_type", "linked_record", ["presentation", "links", "0", "entityType"], remove: true),
        invalid("batch_negative_index", "batch", ["presentation", "recovery", "items", "0", "index"], value: -1),
        invalid("batch_boolean_index", "batch", ["presentation", "recovery", "items", "0", "index"], value: false),
        invalid("batch_fraction_index", "batch", ["presentation", "recovery", "items", "0", "index"], value: 0.5),
        invalid("batch_invalid_target", "batch", ["presentation", "recovery", "items", "0", "targetTaskId"],
                value: "T-1"),
        invalid("batch_missing_original_key", "batch", ["presentation", "recovery", "items", "0", "idempotencyKey"],
                remove: true)
    ]

    private static let categories: [MCPResultErrorCategory] = [
        .invalidInput, .notFound, .ambiguousIdentity, .revisionConflict, .keyConflict, .storageFailure,
        .incoherentCapture, .admissionBusy, .deadlineExceeded, .retentionCapacity, .invalidCursor,
        .expiredCursor, .serializationFailure, .outcomeUncertain, .unclassifiedHistorical, .internalFailure
    ]

    private static func invalid(_ name: String, _ base: String, _ path: [String],
                                value: Any = NSNull(), remove: Bool = false) -> [String: Any] {
        ["name": name, "base": base, "path": path, "value": value, "remove": remove]
    }
}
#endif
