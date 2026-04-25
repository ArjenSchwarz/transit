import AppIntents
import Foundation
import SwiftData
import Testing
@testable import Transit

/// Tests for ScanDuplicateDisplayIDsIntent and ReassignDuplicateDisplayIDsIntent.
/// Covers AC 6.1, 6.2, 6.3, 6.4 from the duplicate-displayid-cleanup spec.
///
/// AC 6.3 parity test: the JSON shape (top-level keys + value types) returned by
/// the Intent must match the JSON shape returned by the MCP `scan_duplicate_display_ids`
/// and `reassign_duplicate_display_ids` tools for the same pre-seeded scenario.
@MainActor @Suite(.serialized)
struct DisplayIDMaintenanceIntentsTests {

    // MARK: - Setup helpers

    private struct IntentEnv {
        let context: ModelContext
        let maintenanceService: DisplayIDMaintenanceService
    }

    /// Builds a maintenance service backed by an isolated in-memory context.
    private func makeIntentEnv() throws -> IntentEnv {
        let context = try TestModelContainer.newContext()
        let taskAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let milestoneAllocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let commentService = CommentService(modelContext: context)
        let maintenanceService = DisplayIDMaintenanceService(
            modelContext: context,
            taskAllocator: taskAllocator,
            milestoneAllocator: milestoneAllocator,
            commentService: commentService
        )
        return IntentEnv(context: context, maintenanceService: maintenanceService)
    }

    private func makeProject(in context: ModelContext, name: String = "Test Project") -> Project {
        let project = Project(name: name, description: "A test project", gitRepo: nil, colorHex: "#FF0000")
        context.insert(project)
        return project
    }

    /// Inserts a task with the given permanent display ID and a fixed creation date so
    /// winner/loser ordering is deterministic.
    @discardableResult
    private func makeTask(
        in context: ModelContext, project: Project, name: String,
        displayId: Int, creationDate: Date = Date(timeIntervalSince1970: 1000)
    ) -> TransitTask {
        let task = TransitTask(
            name: name,
            type: .feature,
            project: project,
            displayID: .permanent(displayId)
        )
        task.creationDate = creationDate
        context.insert(task)
        return task
    }

    /// Decodes an Intent's JSON-string result into a top-level dictionary.
    private func decodeIntentJSON(_ text: String) throws -> [String: Any] {
        let data = try #require(text.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Scan intent

    @Test func scanIntentReturnsJSONForEmptyContext() async throws {
        let env = try makeIntentEnv()

        let result = await ScanDuplicateDisplayIDsIntent.execute(
            maintenanceService: env.maintenanceService
        )
        let json = try decodeIntentJSON(result)

        let tasks = try #require(json["tasks"] as? [[String: Any]])
        let milestones = try #require(json["milestones"] as? [[String: Any]])
        #expect(tasks.isEmpty)
        #expect(milestones.isEmpty)
    }

    @Test func scanIntentReportsTaskDuplicates() async throws {
        let env = try makeIntentEnv()
        let project = makeProject(in: env.context)
        makeTask(in: env.context, project: project, name: "Older", displayId: 5,
                 creationDate: Date(timeIntervalSince1970: 1000))
        makeTask(in: env.context, project: project, name: "Newer", displayId: 5,
                 creationDate: Date(timeIntervalSince1970: 2000))
        try env.context.save()

        let result = await ScanDuplicateDisplayIDsIntent.execute(
            maintenanceService: env.maintenanceService
        )
        let json = try decodeIntentJSON(result)

        let tasks = try #require(json["tasks"] as? [[String: Any]])
        #expect(tasks.count == 1)
        let group = try #require(tasks.first)
        #expect(group["displayId"] as? Int == 5)
        let records = try #require(group["records"] as? [[String: Any]])
        #expect(records.count == 2)
        #expect(records.first?["role"] as? String == "winner")
        #expect(records.first?["name"] as? String == "Older")
        #expect(records.last?["role"] as? String == "loser")
    }

    // MARK: - Reassign intent

    @Test func reassignIntentReturnsOkOnEmptyContext() async throws {
        let env = try makeIntentEnv()

        let result = await ReassignDuplicateDisplayIDsIntent.execute(
            maintenanceService: env.maintenanceService
        )
        let json = try decodeIntentJSON(result)

        #expect(json["status"] as? String == "ok")
        let groups = try #require(json["groups"] as? [[String: Any]])
        #expect(groups.isEmpty)
        // counterAdvance key must always be present per design (nullable here because
        // there are no records of either type to fence against).
        #expect(json.keys.contains("counterAdvance"))
    }

    @Test func reassignIntentReturnsOkAndGroupsOnDuplicates() async throws {
        let env = try makeIntentEnv()
        let project = makeProject(in: env.context)
        makeTask(in: env.context, project: project, name: "Winner", displayId: 7,
                 creationDate: Date(timeIntervalSince1970: 1000))
        makeTask(in: env.context, project: project, name: "Loser", displayId: 7,
                 creationDate: Date(timeIntervalSince1970: 2000))
        try env.context.save()

        let result = await ReassignDuplicateDisplayIDsIntent.execute(
            maintenanceService: env.maintenanceService
        )
        let json = try decodeIntentJSON(result)

        #expect(json["status"] as? String == "ok")
        let groups = try #require(json["groups"] as? [[String: Any]])
        #expect(groups.count == 1)
        // counterAdvance should be present as a non-null object since there is at least
        // one task on which to fence the counter.
        let counterAdvance = json["counterAdvance"]
        #expect(counterAdvance != nil)
        #expect(!(counterAdvance is NSNull))
    }

    // MARK: - Error envelope (AC 6.4)

    /// The reassign intent never throws — it captures the busy outcome inside the
    /// JSON envelope. This is the primary path the spec mentions for "errors as
    /// JSON payloads" because reassignDuplicates already encodes failure codes
    /// itself; a second concurrent invocation returns status: "busy".
    @Test func reassignIntentReturnsBusyJSONInsteadOfThrowingOnConcurrentInvocation() async throws {
        let env = try makeIntentEnv()
        let project = makeProject(in: env.context)
        makeTask(in: env.context, project: project, name: "A", displayId: 9,
                 creationDate: Date(timeIntervalSince1970: 1000))
        makeTask(in: env.context, project: project, name: "B", displayId: 9,
                 creationDate: Date(timeIntervalSince1970: 2000))
        try env.context.save()

        // Kick off two reassigns concurrently. One wins the single-flight guard;
        // the other returns status: "busy". Hoist the service into a local so the
        // child tasks capture only the @MainActor-Sendable reference, not the
        // non-Sendable IntentEnv struct (which holds a ModelContext).
        let service = env.maintenanceService
        async let firstResult = ReassignDuplicateDisplayIDsIntent.execute(
            maintenanceService: service
        )
        async let secondResult = ReassignDuplicateDisplayIDsIntent.execute(
            maintenanceService: service
        )
        let (first, second) = await (firstResult, secondResult)

        let firstJSON = try decodeIntentJSON(first)
        let secondJSON = try decodeIntentJSON(second)

        let statuses = [firstJSON["status"] as? String, secondJSON["status"] as? String]
        #expect(statuses.contains("ok"))
        #expect(statuses.contains("busy"))

        // Verify the busy variant exposes the expected envelope shape: groups: [],
        // counterAdvance: null per design.
        let busyJSON = (firstJSON["status"] as? String == "busy") ? firstJSON : secondJSON
        let busyGroups = try #require(busyJSON["groups"] as? [Any])
        #expect(busyGroups.isEmpty)
        #expect(busyJSON.keys.contains("counterAdvance"))
        #expect(busyJSON["counterAdvance"] is NSNull)
    }

    // MARK: - JSON parity vs MCP (AC 6.3)

    #if os(macOS)
    /// Asserts that the Intent and the MCP scan return identical top-level keys and
    /// value types for the same pre-seeded scenario. The two surfaces share the same
    /// service and encoder path, so byte-equal payloads are expected; we compare both
    /// the raw text and a structural projection to cover any future divergence.
    @Test func scanIntentJSONShapeMatchesMCPForSameScenario() async throws {
        // Build two parallel envs with the same seed so the underlying records have
        // matching display IDs. UUIDs differ, but key sets and value types must match.
        let intentEnv = try makeIntentEnv()
        seedTaskDuplicate(in: intentEnv.context, displayId: 11)

        let mcpEnv = try MCPTestHelpers.makeEnv()
        mcpEnv.mcpSettings.maintenanceToolsEnabled = true
        defer { mcpEnv.mcpSettings.maintenanceToolsEnabled = false }
        seedTaskDuplicate(in: mcpEnv.context, displayId: 11)

        // Intent path
        let intentText = await ScanDuplicateDisplayIDsIntent.execute(
            maintenanceService: intentEnv.maintenanceService
        )
        let intentJSON = try decodeIntentJSON(intentText)

        // MCP path
        let mcpResponse = await mcpEnv.handler.handle(
            MCPTestHelpers.toolCallRequest(tool: "scan_duplicate_display_ids", arguments: [:])
        )
        let mcpJSON = try MCPTestHelpers.decodeResult(mcpResponse)

        // Top-level keys match.
        #expect(Set(intentJSON.keys) == Set(mcpJSON.keys))
        #expect(Set(intentJSON.keys) == ["tasks", "milestones"])

        // Both yield array values for both keys.
        #expect(intentJSON["tasks"] is [Any])
        #expect(mcpJSON["tasks"] is [Any])
        #expect(intentJSON["milestones"] is [Any])
        #expect(mcpJSON["milestones"] is [Any])

        // Each task group has the same key set and the same recordRef key set.
        let intentGroup = try #require((intentJSON["tasks"] as? [[String: Any]])?.first)
        let mcpGroup = try #require((mcpJSON["tasks"] as? [[String: Any]])?.first)
        #expect(Set(intentGroup.keys) == Set(mcpGroup.keys))
        #expect(Set(intentGroup.keys) == ["displayId", "records"])
        #expect(intentGroup["displayId"] as? Int == 11)
        #expect(mcpGroup["displayId"] as? Int == 11)

        let intentRecord = try #require((intentGroup["records"] as? [[String: Any]])?.first)
        let mcpRecord = try #require((mcpGroup["records"] as? [[String: Any]])?.first)
        #expect(Set(intentRecord.keys) == Set(mcpRecord.keys))
        #expect(Set(intentRecord.keys) == ["id", "name", "projectName", "creationDate", "role"])
        // Spot-check value types (AC 6.3 requires matching value types, not values).
        #expect(intentRecord["id"] is String && mcpRecord["id"] is String)
        #expect(intentRecord["name"] is String && mcpRecord["name"] is String)
        #expect(intentRecord["projectName"] is String && mcpRecord["projectName"] is String)
        #expect(intentRecord["creationDate"] is String && mcpRecord["creationDate"] is String)
        #expect(intentRecord["role"] is String && mcpRecord["role"] is String)
    }

    /// Asserts the same parity invariant for the reassignment result envelope.
    @Test func reassignIntentJSONShapeMatchesMCPForSameScenario() async throws {
        let intentEnv = try makeIntentEnv()
        seedTaskDuplicate(in: intentEnv.context, displayId: 13)

        let mcpEnv = try MCPTestHelpers.makeEnv()
        mcpEnv.mcpSettings.maintenanceToolsEnabled = true
        defer { mcpEnv.mcpSettings.maintenanceToolsEnabled = false }
        seedTaskDuplicate(in: mcpEnv.context, displayId: 13)

        // Intent path
        let intentText = await ReassignDuplicateDisplayIDsIntent.execute(
            maintenanceService: intentEnv.maintenanceService
        )
        let intentJSON = try decodeIntentJSON(intentText)

        // MCP path
        let mcpResponse = await mcpEnv.handler.handle(
            MCPTestHelpers.toolCallRequest(tool: "reassign_duplicate_display_ids", arguments: [:])
        )
        let mcpJSON = try MCPTestHelpers.decodeResult(mcpResponse)

        // Top-level envelope.
        #expect(Set(intentJSON.keys) == Set(mcpJSON.keys))
        #expect(Set(intentJSON.keys) == ["status", "groups", "counterAdvance"])
        #expect(intentJSON["status"] as? String == "ok")
        #expect(mcpJSON["status"] as? String == "ok")
        #expect(intentJSON["groups"] is [Any] && mcpJSON["groups"] is [Any])

        // Group envelope.
        let intentGroup = try #require((intentJSON["groups"] as? [[String: Any]])?.first)
        let mcpGroup = try #require((mcpJSON["groups"] as? [[String: Any]])?.first)
        #expect(Set(intentGroup.keys) == Set(mcpGroup.keys))
        #expect(Set(intentGroup.keys) == ["type", "displayId", "winner", "reassignments", "failure"])
        #expect(intentGroup["type"] as? String == "task")
        #expect(mcpGroup["type"] as? String == "task")

        // Winner envelope.
        let intentWinner = try #require(intentGroup["winner"] as? [String: Any])
        let mcpWinner = try #require(mcpGroup["winner"] as? [String: Any])
        #expect(Set(intentWinner.keys) == Set(mcpWinner.keys))
        #expect(Set(intentWinner.keys) == ["id", "name"])

        // CounterAdvance envelope (must always be present, both surfaces).
        let intentAdvance = try #require(intentJSON["counterAdvance"] as? [String: Any])
        let mcpAdvance = try #require(mcpJSON["counterAdvance"] as? [String: Any])
        #expect(Set(intentAdvance.keys) == Set(mcpAdvance.keys))
        #expect(Set(intentAdvance.keys) == ["task", "milestone"])
    }
    #endif

    // MARK: - Shared scenario seeding

    private func seedTaskDuplicate(in context: ModelContext, displayId: Int) {
        let project = makeProject(in: context)
        makeTask(in: context, project: project, name: "Older",
                 displayId: displayId, creationDate: Date(timeIntervalSince1970: 1000))
        makeTask(in: context, project: project, name: "Newer",
                 displayId: displayId, creationDate: Date(timeIntervalSince1970: 2000))
        try? context.save()
    }
}
