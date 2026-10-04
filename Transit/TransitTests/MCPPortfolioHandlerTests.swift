#if os(macOS)
import Foundation
import SwiftData
import Testing

// swiftlint:disable file_length
@testable import Transit

/// Public-dispatch preparation: these tests intentionally require the shared registry and handler wiring.
/// They do not bypass the tools/call boundary or invent a capture/preparation injection interface.
@MainActor @Suite(.serialized)
struct MCPPortfolioHandlerTests {
    @Test func advertisedToolContainsStrictSummaryBranchesAndSemanticDescription() async throws {
        let env = try makeEnvironment()
        let response = try await listResponse(env)
        let wire = try envelope(response)
        let result = try #require(wire["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        let tool = try #require(tools.first { $0["name"] as? String == "query_project_summaries" })
        #expect(tools.filter { $0["name"] as? String == "query_project_summaries" }.count == 1)
        let schema = try #require(tool["inputSchema"] as? [String: Any])
        let branches = try #require(schema["oneOf"] as? [[String: Any]])
        #expect(branches.count == 5)
        #expect(branches.allSatisfy { $0["additionalProperties"] as? Bool == false })
        let required = branches.compactMap { $0["required"] as? [String] }.map(Set.init)
        #expect(required.contains(Set(["start", "end", "limit"])))
        #expect(required.contains(Set(["start", "end", "limit", "projectId"])))
        #expect(required.contains(Set(["start", "end", "limit", "project"])))
        #expect(required.contains(Set(["snapshotId"])) && required.contains(Set(["cursor"])))
        for branch in branches where (branch["required"] as? [String] ?? []).contains("start") {
            let properties = try #require(branch["properties"] as? [String: Any])
            try expectBoundedLimit(properties)
            let policy = try #require(properties["readPolicy"] as? [String: Any])
            #expect(policy["default"] as? String == "refresh_if_needed")
        }
        let cursorBranch = try #require(branches.first { ($0["required"] as? [String]) == ["cursor"] })
        let cursorProperties = try #require(cursorBranch["properties"] as? [String: Any])
        #expect((cursorProperties["readPolicy"] as? [String: Any])?["default"] == nil)
        let description = try #require(tool["description"] as? String)
        let normalizedDescription = description.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for fragment in [
            "activeTaskCount", "nonterminal", "[start,end)", "historical", "sampleComplete",
            "five seconds", "five minutes", "Each HTTP POST accepts one JSON-RPC object",
            "JSON-RPC batch arrays are rejected",
            "mutate_tasks can carry multiple application-level operations within one tools/call",
            "READ_TIMEOUT", "storage_failure",
            "incoherent_capture", "serialization_failure", "remote"
        ] {
            #expect(normalizedDescription.contains(fragment), "Missing advertised semantics: \(fragment)")
        }
    }

    @Test func advertisedSnapshotTaskBranchPreservesOrdinaryQuerySchema() async throws {
        let env = try makeEnvironment()
        let response = try await listResponse(env)
        let tools = try #require(
            (try envelope(response)["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let tool = try #require(tools.first { $0["name"] as? String == "query_tasks" })
        let schema = try #require(tool["inputSchema"] as? [String: Any])
        let branches = try #require(schema["oneOf"] as? [[String: Any]])
        let snapshot = try #require(
            branches.first {
                Set($0["required"] as? [String] ?? [])
                    == Set(["snapshotId", "detailLevel", "includeComments", "limit"])
            })
        #expect(snapshot["additionalProperties"] as? Bool == false)
        let properties = try #require(snapshot["properties"] as? [String: Any])
        #expect(
            Set(properties.keys)
                == Set(["snapshotId", "detailLevel", "includeComments", "limit", "projectId", "status"]))
        try expectBoundedLimit(properties)
        #expect((properties["includeComments"] as? [String: Any])?["const"] as? Bool == false)
        #expect(branches.contains { ($0["properties"] as? [String: Any])?["taskIds"] != nil })
        let description = try #require(tool["description"] as? String)
        for fragment in ["stored-status", "effective", "comment", "revision", "scope", "empty"] {
            #expect(description.contains(fragment))
        }
    }

    @Test func summaryRejectsMalformedScalarsSelectorsWindowsAndUnknownFields() async throws {
        let env = try makeEnvironment()
        let invalid: [[String: Any]] = [
            [:], ["start": 12], ["end": NSNull()], ["limit": true], ["limit": 1.5],
            ["limit": "1"], ["limit": 0], ["limit": 101], ["projectId": "bad-uuid"],
            ["project": " \n "], ["project": 1], ["readPolicy": "fresh"], ["extra": "ignored"],
            ["projectId": projectID.uuidString, "project": "Alpha"],
            ["start": "2026-10-03"], ["end": "2026-10-03T01:00:00"],
            ["start": "2026-02-30T00:00:00Z"], ["start": "2026-10-03T00:00:00.1234Z"],
            ["end": "2026-10-03T00:00:00Z"]
        ]
        for replacement in invalid {
            let arguments =
                replacement.isEmpty ? [:] : initialArguments.merging(replacement) { _, new in new }
            let response = try await call(env, tool: "query_project_summaries", arguments: arguments)
            try expectError(response, code: "INVALID_INPUT")
        }
        for endpoint in ["start", "end", "limit"] {
            var arguments = initialArguments
            arguments.removeValue(forKey: endpoint)
            try expectError(
                try await call(env, tool: "query_project_summaries", arguments: arguments),
                code: "INVALID_INPUT")
        }
    }

    @Test func replayAndContinuationAreExclusiveAndDoNotSilentlyBecomeInitialReads() async throws {
        let env = try makeEnvironment()
        let invalid: [(arguments: [String: Any], code: String)] = [
            (["snapshotId": "bad"], "INVALID_SNAPSHOT"),
            (["snapshotId": projectID.uuidString, "limit": 1], "INVALID_INPUT"),
            (["snapshotId": projectID.uuidString, "readPolicy": "cached"], "INVALID_INPUT"),
            (["cursor": "bad"], "INVALID_CURSOR"),
            (["cursor": reusableCursor, "start": initialArguments["start"]!], "INVALID_INPUT"),
            (["cursor": reusableCursor, "readPolicy": "fresh"], "INVALID_INPUT")
        ]
        for entry in invalid {
            try expectError(
                try await call(env, tool: "query_project_summaries", arguments: entry.arguments),
                code: entry.code)
        }
        try expectError(
            try await call(
                env, tool: "query_project_summaries",
                arguments: ["snapshotId": UUID().uuidString]), code: "INVALID_SNAPSHOT")
        try expectError(
            try await call(
                env, tool: "query_project_summaries",
                arguments: ["cursor": reusableCursor]), code: "INVALID_CURSOR")
    }

    @Test func snapshotTaskModeValidatesOptionsBeforeOrdinaryParsing() async throws {
        let env = try makeEnvironment()
        let baseline: [String: Any] = [
            "snapshotId": projectID.uuidString, "detailLevel": "full",
            "includeComments": false, "limit": 10
        ]
        let cases: [(patch: [String: Any], code: String)] = [
            (["includeComments": true], "SNAPSHOT_INCOMPATIBLE"),
            (["project": "Alpha"], "SNAPSHOT_INCOMPATIBLE"),
            (["readPolicy": "cached"], "SNAPSHOT_INCOMPATIBLE"),
            (["search": "Task"], "SNAPSHOT_INCOMPATIBLE"),
            (["type": "feature"], "SNAPSHOT_INCOMPATIBLE"),
            (["priority": "high"], "SNAPSHOT_INCOMPATIBLE"),
            (["detailLevel": "expanded"], "INVALID_INPUT"),
            (["includeComments": "false"], "INVALID_INPUT"),
            (["limit": true], "INVALID_INPUT"),
            (["status": ["unknown"]], "INVALID_INPUT"),
            (["projectId": "bad"], "INVALID_INPUT")
        ]
        for entry in cases {
            try expectError(
                try await call(
                    env, tool: "query_tasks",
                    arguments: baseline.merging(entry.patch) { _, new in new }), code: entry.code)
        }
        for required in ["detailLevel", "includeComments", "limit"] {
            var arguments = baseline
            arguments.removeValue(forKey: required)
            try expectError(
                try await call(env, tool: "query_tasks", arguments: arguments), code: "INVALID_INPUT")
        }
    }

    @Test func normalizedNameResolutionAndMissingSelectorsHaveExplicitOutcomes() async throws {
        let env = try makeEnvironment()
        let selected = try await summary(env, patch: ["project": "  aLPHa \n"])
        let projects = try #require(selected.payload["projects"] as? [[String: Any]])
        #expect(projects.count == 1 && projects.first?["projectId"] as? String == projectID.uuidString)
        try expectError(
            try await call(
                env, tool: "query_project_summaries",
                arguments: initialArguments.merging(["projectId": UUID().uuidString]) { _, new in new }),
            code: "PROJECT_NOT_FOUND")
        let collision = MCPTestHelpers.makeProject(in: env.context, name: " ALPHA ")
        collision.id = UUID()
        try env.context.save()
        try expectError(
            try await call(
                env, tool: "query_project_summaries",
                arguments: initialArguments.merging(["project": "alpha"]) { _, new in new }),
            code: "AMBIGUOUS_PROJECT")
    }

    @Test func populatedSummaryHasCompactCountsWindowAndExternalCaptureMetadata() async throws {
        let env = try makeEnvironment()
        let result = try await summary(env)
        let projects = try #require(result.payload["projects"] as? [[String: Any]])
        let project = try #require(projects.first { $0["projectId"] as? String == projectID.uuidString })
        let buckets = try #require(project["countsByStatus"] as? [String: Int])
        #expect(
            buckets == [
                "idea": 2, "planning": 1, "spec": 1, "ready-for-implementation": 1,
                "in-progress": 1, "ready-for-review": 1, "done": 1, "abandoned": 1
            ])
        #expect(project["totalTaskCount"] as? Int == 9 && project["nonterminalTaskCount"] as? Int == 7)
        let window = try #require(result.payload["completionWindow"] as? [String: String])
        #expect(window == ["start": "2026-10-03T00:00:00.000Z", "end": "2026-10-03T01:00:00.000Z"])
        #expect(result.payload["_meta"] == nil && result.payload["snapshotId"] == nil)
        #expect(result.metadata["snapshotId"] is String && result.metadata["asOf"] is String)
        #expect(result.metadata["freshness"] is [String: Any] && result.metadata["read"] is [String: Any])
        let text = String(
            data: try JSONSerialization.data(withJSONObject: result.payload), encoding: .utf8)!
        #expect(
            !text.contains("Secret description") && !text.contains("Secret comment")
                && !text.contains("Secret metadata"))
    }

    @Test func emptyPortfolioAndEmptyScopedProjectStillCarryReadEvidence() async throws {
        let empty = try makeEnvironment(taskCount: 0, projectCount: 0)
        let portfolio = try await summary(empty)
        #expect((portfolio.payload["projects"] as? [[String: Any]])?.isEmpty == true)
        #expect(portfolio.metadata["snapshotId"] is String && portfolio.metadata["asOf"] is String)
        let env = try makeEnvironment(taskCount: 0)
        let scoped = try await summary(env, patch: ["projectId": projectID.uuidString])
        let projects = try #require(scoped.payload["projects"] as? [[String: Any]])
        #expect(projects.count == 1 && projects.first?["totalTaskCount"] as? Int == 0)
        #expect(projects.first?["lastRecordedActivity"] is NSNull)
        #expect(scoped.metadata["freshness"] is [String: Any] && scoped.metadata["read"] is [String: Any])
    }
}

extension MCPPortfolioHandlerTests {
    @Test func summaryReplayAndContinuationPreserveOriginalPayloadAndEvidenceAfterSavedChanges()
        async throws {
        let env = try makeEnvironment()
        let first = try await summary(env, patch: ["limit": 1])
        let snapshot = try #require(first.metadata["snapshotId"] as? String)
        let cursor = try #require(first.payload["nextCursor"] as? String)
        #expect(MCPCursorFamily.classify(cursor) == .reusable)
        let project = try #require(
            try env.context.fetch(FetchDescriptor<Project>()).first { $0.id == projectID })
        project.name = "Changed after capture"
        for task in try env.context.fetch(FetchDescriptor<TransitTask>()) { env.context.delete(task) }
        try env.context.save()
        let replay = try decode(
            try await call(env, tool: "query_project_summaries", arguments: ["snapshotId": snapshot]))
        #expect(equalJSON(replay.payload, first.payload) && equalJSON(replay.metadata, first.metadata))
        let next = try decode(
            try await call(env, tool: "query_project_summaries", arguments: ["cursor": cursor]))
        #expect(equalJSON(next.metadata, first.metadata))
        #expect(equalJSON(next.payload["completionWindow"], first.payload["completionWindow"]))
        #expect(next.payload["expiresAt"] as? String == first.payload["expiresAt"] as? String)
        #expect((next.payload["projects"] as? [[String: Any]])?.first?["name"] as? String == "Beta")
        try expectError(
            try await call(
                env, tool: "query_project_summaries",
                arguments: ["cursor": cursor, "readPolicy": "refresh_if_needed"]),
            code: "SNAPSHOT_INCOMPATIBLE")
    }

    @Test func snapshotTaskDetailsReconcileAndRetainCapturedRevisionAcrossLiveDeletion() async throws {
        let env = try makeEnvironment()
        let original = try await summary(env)
        let snapshot = try #require(original.metadata["snapshotId"] as? String)
        let source = try #require(
            try env.context.fetch(FetchDescriptor<TransitTask>()).first { $0.permanentDisplayId == 9 })
        let revision = try MCPRecordSnapshot.task(source, in: env.context).revision
        let query: [String: Any] = [
            "snapshotId": snapshot, "detailLevel": "full", "includeComments": false,
            "limit": 1, "projectId": projectID.uuidString, "status": ["idea", "idea"]
        ]
        let first = try decode(try await call(env, tool: "query_tasks", arguments: query))
        var rows = try #require(first.payload["results"] as? [[String: Any]])
        let cursor = try #require(first.payload["nextCursor"] as? String)
        #expect(
            MCPCursorFamily.classify(cursor) == .reusable && equalJSON(first.metadata, original.metadata))
        env.context.delete(source)
        try env.context.save()
        let continuation = try decode(
            try await call(env, tool: "query_tasks", arguments: ["cursor": cursor]))
        rows += try #require(continuation.payload["results"] as? [[String: Any]])
        #expect(rows.count == 2 && rows.allSatisfy { $0["status"] as? String == "idea" })
        let legacy = try #require(rows.first { $0["storedStatus"] as? String == "legacy-status" })
        #expect(legacy["revision"] as? String == revision)
        #expect(legacy["description"] as? String == "Secret description 8")
        #expect((legacy["metadata"] as? [String: String])?["fixture"] == "Secret metadata 8")
        #expect(rows.allSatisfy { $0["comments"] == nil })
        #expect(equalJSON(continuation.metadata, original.metadata))
        #expect(continuation.payload["expiresAt"] as? String == first.payload["expiresAt"] as? String)
    }

    @Test func scopedSnapshotsCannotExpandToForeignProjects() async throws {
        let env = try makeEnvironment()
        let original = try await summary(env, patch: ["projectId": projectID.uuidString])
        let snapshot = try #require(original.metadata["snapshotId"] as? String)
        let foreign = try #require(
            try env.context.fetch(FetchDescriptor<Project>()).first { $0.id != projectID })
        try expectError(
            try await call(
                env, tool: "query_tasks",
                arguments: [
                    "snapshotId": snapshot, "detailLevel": "summary", "includeComments": false,
                    "limit": 10, "projectId": foreign.id.uuidString
                ]), code: "SNAPSHOT_INCOMPATIBLE")
    }

    @Test func missingReusableCursorAndOrdinaryCursorFamiliesRemainDistinct() async throws {
        let env = try makeEnvironment()
        try expectError(
            try await call(env, tool: "query_tasks", arguments: ["cursor": reusableCursor]),
            code: "INVALID_CURSOR")
        let ordinary = try decode(try await call(env, tool: "query_tasks", arguments: ordinaryArguments(["limit": 1])))
        let cursor = try #require(ordinary.payload["nextCursor"] as? String)
        #expect(MCPCursorFamily.classify(cursor) == .ordinary)
        let next = try decode(try await call(env, tool: "query_tasks", arguments: ["cursor": cursor]))
        #expect((next.payload["results"] as? [[String: Any]])?.count == 1)
        #expect(equalJSON(next.metadata, ordinary.metadata))
    }

    @Test(arguments: ["storage_failure", "serialization_failure", "incoherent_capture"])
    func admittedCaptureSourceFailuresKeepTheirCategoryWithoutInventingSnapshot(category: String)
        async throws {
        let failure: MCPReadCaptureError
        switch category {
        case "storage_failure": failure = .storageFailure
        case "serialization_failure": failure = .serializationFailure
        default: failure = .incoherentCapture
        }
        let env = try makeEnvironment(captureFailure: failure)
        for tool in ["query_tasks", "query_project_summaries"] {
            let arguments: [String: Any] = tool == "query_tasks" ? ordinaryArguments() : initialArguments
            let bytes = try await call(env, tool: tool, arguments: arguments)
            let wire = try envelope(bytes)
            #expect(wire["error"] == nil)
            let result = try #require(wire["result"] as? [String: Any])
            #expect(result["isError"] as? Bool == true)
            let read = try #require(
                (result["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] as? [String: Any])
            #expect(read["category"] as? String == category)
            let requestID = try #require(read["requestId"] as? String)
            #expect(UUID(uuidString: requestID) != nil)
            #expect(read["snapshotId"] == nil && read["asOf"] == nil && read["freshness"] == nil)
            let execution = try #require(read["read"] as? [String: Any])
            #expect(execution["policy"] as? String == "cached" && execution["budgetMs"] as? Int == 5_000)
            // This observes a real typed producer failure inside the admitted worker, not outer encode fallback.
            let content = try #require(result["content"] as? [[String: Any]])
            let text = try #require(content.first?["text"] as? String)
            #expect(!text.isEmpty)
            // Non-query failures use plain text; their typed category lives in external metadata.
        }
    }

    @Test func ninthTinyCapturedSummaryNormalizesPreGateCapacityWithoutEvictingRoots() async throws {
        let env = try makeEnvironment(taskCount: 0, projectCount: 0)
        let store = try env.handler.reusableSnapshots.get()
        var roots: [RetainedView] = []
        for _ in 0..<8 { roots.append(try seedEmptyReusableRoot(env, store: store)) }
        let before = try store.domain.accounting(for: store.publicationStoreID)
        #expect(before.visibleEntries == 8 && before.pendingEntries == 0)
        let response = try await call(env, tool: "query_project_summaries", arguments: initialArguments)
        try expectError(response, code: "QUERY_CAPACITY_EXCEEDED")
        let after = try store.domain.accounting(for: store.publicationStoreID)
        #expect(after.visibleEntries == 8 && after.visibleBytes == before.visibleBytes)
        #expect(after.pendingEntries == 0 && after.pendingBytes == 0)
        for root in roots {
            #expect(try store.retainedView(for: root.capture.metadata.snapshotId, now: .now)
                .capture.metadata.snapshotId == root.capture.metadata.snapshotId)
        }
    }

    @Test(arguments: ["summary_replay", "summary_cursor", "task_snapshot", "task_cursor"])
    func preGateExpiredReusableLookupsKeepTheirFamilyError(mode: String) async throws {
        let env = try makeEnvironment(taskCount: 0, projectCount: 0)
        let store = try env.handler.reusableSnapshots.get()
        let root = try seedEmptyReusableRoot(env, store: store, cursor: reusableCursor)
        let before = try store.domain.accounting(for: store.publicationStoreID)
        store.domain.setTestingInstant(root.capture.retentionDeadline + .milliseconds(1))
        let tool = mode.hasPrefix("summary_") ? "query_project_summaries" : "query_tasks"
        let arguments: [String: Any]
        switch mode {
        case "summary_replay": arguments = ["snapshotId": root.capture.metadata.snapshotId]
        case "task_snapshot":
            arguments = ["snapshotId": root.capture.metadata.snapshotId, "detailLevel": "summary",
                         "includeComments": false, "limit": 1]
        default: arguments = ["cursor": reusableCursor]
        }
        let code = mode.hasSuffix("cursor") ? "INVALID_CURSOR" : "INVALID_SNAPSHOT"
        try expectError(try await call(env, tool: tool, arguments: arguments), code: code)
        let accounting = try store.domain.accounting(for: store.publicationStoreID)
        #expect(accounting.visibleEntries <= before.visibleEntries && accounting.visibleBytes <= before.visibleBytes)
        #expect(accounting.pendingEntries == 0 && accounting.pendingBytes == 0)
    }

    @Test func cachedAndDefaultPolicyAreAdvertisedInExecutionMetadata() async throws {
        let env = try makeEnvironment(taskCount: 0)
        let cached = try await summary(env)
        let cachedRead = try #require(cached.metadata["read"] as? [String: Any])
        #expect(
            cachedRead["policy"] as? String == "cached"
                && cachedRead["refreshOutcome"] as? String == "not_requested")
        var arguments = initialArguments
        arguments.removeValue(forKey: "readPolicy")
        let automatic = try decode(
            try await call(env, tool: "query_project_summaries", arguments: arguments))
        let read = try #require(automatic.metadata["read"] as? [String: Any])
        #expect(read["policy"] as? String == "refresh_if_needed" && read["budgetMs"] as? Int == 5_000)
    }

    @Test func fallbackStorageAllowsSummaryReadAndReportsLocalEvidence() async throws {
        let env = try makeEnvironment(persistence: FallbackOutcomeFixture.degraded)
        let result = try await summary(env)
        #expect((result.payload["projects"] as? [[String: Any]])?.count == 2)
        #expect(result.metadata["snapshotId"] is String)
    }

    @Test func ordinaryQueriesRetainRawStatusOrderingFieldsAndLegacyNonterminalCount() async throws {
        let env = try makeEnvironment()
        let ideas = try queryResults(
            try await call(env, tool: "query_tasks", arguments: ordinaryArguments(["status": ["idea"]])))
        #expect(ideas.count == 1 && ideas.first?["displayId"] as? Int == 1)
        let all = try queryResults(
            try await call(env, tool: "query_tasks", arguments: ordinaryArguments()))
        #expect(
            all.count == 9
                && all.contains { $0["status"] as? String == "legacy-status" && $0["displayId"] as? Int == 9 })
        #expect(
            all.allSatisfy { $0["revision"] == nil && $0["description"] == nil && $0["comments"] == nil })
        let ids = all.compactMap { $0["taskId"] as? String }
        #expect(ids == ids.sorted())
        let projects = try arrayResult(
            try await call(env, tool: "get_projects", arguments: [:]))
        #expect(
            projects.first { $0["projectId"] as? String == projectID.uuidString }?["activeTaskCount"]
                as? Int
                == 7)
    }
}

extension MCPPortfolioHandlerTests {
    private var projectID: UUID { MCPPortfolioFixture.populatedProjectID }
    private var reusableCursor: String { "00000000-0000-8000-8000-000000000099" }
    private var initialArguments: [String: Any] {
        [
            "start": "2026-10-03T00:00:00Z", "end": "2026-10-03T01:00:00Z", "limit": 100,
            "readPolicy": "cached"
        ]
    }

    private func ordinaryArguments(_ patch: [String: Any] = [:]) -> [String: Any] {
        var arguments: [String: Any] = [
            "detailLevel": "summary", "includeComments": false, "limit": 100,
            "readPolicy": "cached"
        ]
        arguments.merge(patch) { _, replacement in replacement }
        return arguments
    }

    @MainActor private final class FailingCaptureSource: MCPReadCaptureSource {
        let error: MCPReadCaptureError
        init(error: MCPReadCaptureError) { self.error = error }
        func capture(_ request: ReadCaptureRequest) throws -> CapturedReadView { throw error }
    }

    // swiftlint:disable:next function_body_length
    private func makeEnvironment(
        taskCount: Int = 9, projectCount: Int = 2, persistence: PersistenceAvailability? = nil,
        captureFailure: MCPReadCaptureError? = nil
    ) throws -> MCPTestEnv {
        // makeEnv owns the in-memory, CloudKit-none TestModelContainer centrally.
        let availability = persistence ?? FallbackOutcomeFixture.makeHealthy()
        let base = try MCPTestHelpers.makeEnv(persistence: availability)
        let domain = MCPReadPublicationDomain()
        let snapshots = MCPTaskQuerySnapshotStore(domain: domain)
        let coordinator = MCPReadCoordinator(domain: domain)
        let monitor = MCPImportEvidenceMonitor(syncActive: false, storeIdentifier: nil)
        let builder = MCPReadCaptureBuilder(
            container: base.context.container, fence: .actorOnlyTestFixture,
            fetchTasks: { context in
                if let captureFailure { throw captureFailure }
                return try context.fetch(FetchDescriptor<TransitTask>())
            }
        )
        let source: any MCPReadCaptureSource = captureFailure == .serializationFailure
            ? FailingCaptureSource(error: .serializationFailure) : builder
        let readService = MCPReadService(source: source, monitor: monitor, snapshots: snapshots,
            pagePreparer: { try MCPModernProviderBinding.prepareReadPages($0, tool: $1, operation: $2) })
        let handler = MCPToolHandler(
            taskService: base.taskService, projectService: base.projectService,
            commentService: base.commentService, milestoneService: base.milestoneService,
            maintenanceService: base.maintenanceService, settings: base.mcpSettings,
            persistence: availability, taskQuerySnapshots: snapshots,
            writeCoordinator: base.writeCoordinator,
            readService: readService, readCoordinator: coordinator
        )
        // The delivered initializer registers its default reusable store in this same publication domain.
        // Portfolio owner helpers remain explicit task-12 scaffolds; no alternate store injection is needed.
        let env = MCPTestEnv(
            handler: handler, taskService: base.taskService, projectService: base.projectService,
            commentService: base.commentService, milestoneService: base.milestoneService,
            maintenanceService: base.maintenanceService, mcpSettings: base.mcpSettings,
            context: base.context, writeCoordinator: base.writeCoordinator,
            sidecarDirectory: base.sidecarDirectory
        )
        env.context.autosaveEnabled = false
        guard projectCount > 0 else { return env }
        let project = MCPTestHelpers.makeProject(in: env.context, name: "Alpha")
        project.id = projectID
        if projectCount > 1 {
            let empty = MCPTestHelpers.makeProject(in: env.context, name: "Beta")
            empty.id = MCPPortfolioFixture.emptyProjectID
        }
        let statuses = MCPSnapshotTaskQueryRequest.supportedStatuses + ["legacy-status"]
        for index in 0..<taskCount {
            let task = TransitTask(
                name: "Task \(index)", type: .feature, project: project, displayID: .permanent(index + 1))
            task.id = UUID(uuidString: String(format: "00000000-0000-4001-8000-%012d", index + 1))!
            task.statusRawValue = statuses[index % statuses.count]
            task.creationDate = MCPPortfolioFixture.window.start.addingTimeInterval(-60)
            task.lastStatusChangeDate = task.creationDate
            task.taskDescription = "Secret description \(index)"
            task.metadata = ["fixture": "Secret metadata \(index)"]
            if task.statusRawValue == "done" { task.completionDate = MCPPortfolioFixture.window.start }
            if task.statusRawValue == "abandoned" { task.completionDate = MCPPortfolioFixture.window.end }
            env.context.insert(task)
            let comment = Comment(
                content: "Secret comment \(index)", authorName: "Test", isAgent: false, task: task)
            comment.creationDate = task.creationDate
            env.context.insert(comment)
        }
        try env.context.save()
        return env
    }

    /// Seed a truthful empty saved capture through the already-implemented store, not scaffold handlers.
    private func seedEmptyReusableRoot(
        _ env: MCPTestEnv, store: MCPReusableSnapshotStore, cursor: String? = nil
    ) throws -> RetainedView {
        let capture = try MCPReadCaptureBuilder(container: env.context.container, fence: .actorOnlyTestFixture)
            .capture(ReadCaptureRequest(projectSelectors: nil, selection: .portfolio,
                                        completeness: .completePortfolio, includeComments: false))
        #expect(capture.projects.isEmpty && capture.tasks.isEmpty && capture.milestones.isEmpty)
        let metadata = try JSONEncoder().encode(capture.metadata)
        let counts = Dictionary(uniqueKeysWithValues: MCPSnapshotTaskQueryRequest.supportedStatuses.map { ($0, 0) })
        let empty: [String: Any] = ["countsByStatus": counts, "totalTaskCount": 0,
            "recentCompletions": ["done": 0, "abandoned": 0, "missingCompletionDateCount": 0]]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let asOf = try #require(formatter.date(from: capture.metadata.asOf))
        let duration = capture.createdAt.duration(to: capture.retentionDeadline).components
        let retainedSeconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        let expiry = MCPRecordSnapshot.timestamp(asOf.addingTimeInterval(retainedSeconds))
        let payload: [String: Any] = ["projects": [], "unresolvedProjects": empty, "diagnostics": [],
            "completionWindow": ["start": "2026-10-03T00:00:00.000Z", "end": "2026-10-03T01:00:00.000Z"],
            "nextCursor": cursor as Any? ?? NSNull(), "expiresAt": expiry]
        let root = RetainedView(capture: capture, frozenMetadataBytes: metadata,
            window: MCPPortfolioFixture.window, initialRequest: try MCPPortfolioSummaryRequest.parse(initialArguments),
            firstPage: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
        let pages = try cursor.map { _ in [try JSONSerialization.data(withJSONObject: [
            "projects": [], "unresolvedProjects": empty, "diagnostics": [],
            "completionWindow": payload["completionWindow"]!, "nextCursor": NSNull(), "expiresAt": expiry
        ], options: [.sortedKeys])] } ?? []
        let bundle = EncodedViewBundle(root: root, pages: pages, cursors: cursor.map { [$0] } ?? [],
                                       encodedCaptureByteCount: metadata.count)
        let reservation = try store.reserveCreate(bundle: bundle, publicationDeadline: capture.retentionDeadline)
        let publication = try store.prepare(reservation: reservation)
        try store.domain.withLock {
            if let rejection = publication.validateLocked(in: store.domain) { throw rejection }
            publication.commitLocked(in: store.domain)
        }
        return root
    }

    private func call(_ env: MCPTestEnv, tool: String, arguments: [String: Any]) async throws -> Data {
        let rpc = MCPTestHelpers.toolCallRequest(tool: tool, arguments: arguments, id: 2382)
        let bytes: Data
        if ["query_project_summaries", "query_tasks", "get_projects"].contains(tool) {
            // Classifier registration is part of task 10; never fabricate an admitted portfolio request.
            let classified = try #require(
                MCPBoundedReadDispatcher.classify(rpc),
                "Covered read must be registered with the authoritative bounded dispatcher: \(tool)")
            bytes = try await MCPBoundedReadDispatcher.response(
                for: classified, rpc: rpc, handler: env.handler,
                coordinator: env.handler.readCoordinator, admittedAt: .now
            )
        } else {
            let response = try #require(await env.handler.handle(rpc))
            bytes = try JSONEncoder().encode(response)
        }
        #expect(try envelope(bytes)["id"] as? Int == 2382)
        return bytes
    }

    private func listResponse(_ env: MCPTestEnv) async throws -> Data {
        let response = try #require(
            await env.handler.handle(MCPTestHelpers.request(method: "tools/list")))
        return try JSONEncoder().encode(response)
    }

    private func summary(_ env: MCPTestEnv, patch: [String: Any] = [:]) async throws -> WireResult {
        try decode(
            try await call(
                env, tool: "query_project_summaries",
                arguments: initialArguments.merging(patch) { _, new in new }))
    }

    private struct WireResult {
        let payload: [String: Any]
        let metadata: [String: Any]
    }

    private func decode(_ response: Data) throws -> WireResult {
        #expect(try envelope(response)["error"] == nil)
        let result = try #require(try envelope(response)["result"] as? [String: Any])
        #expect(result["isError"] as? Bool != true)
        let payload = try self.payload(response)
        let metadata = try #require(
            (result["_meta"] as? [String: Any])?["me.nore.ig.transit/read"] as? [String: Any])
        return WireResult(payload: payload, metadata: metadata)
    }

    private func envelope(_ response: Data) throws -> [String: Any] {
        try #require(
            try JSONSerialization.jsonObject(with: response) as? [String: Any])
    }

    private func expectBoundedLimit(_ properties: [String: Any]) throws {
        let limit = try #require(properties["limit"] as? [String: Any])
        #expect(limit["minimum"] as? Int == 1 && limit["maximum"] as? Int == 100)
    }

    private func contentValue(_ response: Data) throws -> Any {
        let result = try #require(try envelope(response)["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let text = try #require(content.first?["text"] as? String)
        return try JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    private func payload(_ response: Data) throws -> [String: Any] {
        try #require(try contentValue(response) as? [String: Any])
    }

    private func queryResults(_ response: Data) throws -> [[String: Any]] {
        try #require(try payload(response)["results"] as? [[String: Any]])
    }

    private func arrayResult(_ response: Data) throws -> [[String: Any]] {
        try #require(try contentValue(response) as? [[String: Any]])
    }

    private func isError(_ response: Data) throws -> Bool {
        (try envelope(response)["result"] as? [String: Any])?["isError"] as? Bool == true
    }

    private func expectError(_ response: Data, code: String) throws {
        #expect(try envelope(response)["error"] == nil)
        #expect(try isError(response))
        let payload = try self.payload(response)
        let error = try #require(payload["error"] as? [String: Any])
        #expect(error["code"] as? String == code)
        #expect(payload["projects"] == nil && payload["results"] == nil && payload["nextCursor"] == nil)
        if let read = ((try envelope(response)["result"] as? [String: Any])?["_meta"] as? [String: Any])?[
            "me.nore.ig.transit/read"] as? [String: Any] {
            #expect(read["snapshotId"] == nil && read["asOf"] == nil)
            if ["QUERY_CAPACITY_EXCEEDED", "INVALID_SNAPSHOT", "INVALID_CURSOR", "SNAPSHOT_INCOMPATIBLE"]
                .contains(code) {
                #expect(read["category"] as? String != "storage_failure")
            }
        }
    }

    private func equalJSON(_ first: Any?, _ second: Any?) -> Bool {
        guard let first, let second else { return first == nil && second == nil }
        return NSDictionary(dictionary: ["value": first]).isEqual(to: ["value": second])
    }
}
#endif
