#if os(macOS)
import Foundation

/// Portfolio-owned descriptors; shared registration and dispatch remain the shared MCP owner's responsibility.
nonisolated enum MCPPortfolioToolDefinitions {
    static let queryProjectSummaries = MCPToolDefinition(
        name: "query_project_summaries",
        description: """
        Read saved project and milestone summaries from one coherent, reusable snapshot. Supply start, end and
        limit (1...100), optionally projectId or project (exclusive selectors). No selector includes the whole
        portfolio, including empty projects. Project names use normalized exact matching; ambiguity fails.
        Pending local edits are excluded. This does not guarantee that every remote change has been imported.

        countsByStatus contains all eight statuses, including zeros; totalTaskCount is their sum. ideaCount
        counts idea; inProgressCount counts only in-progress; workflowTaskCount counts planning, spec,
        ready-for-implementation, in-progress and ready-for-review; nonterminalTaskCount adds idea to workflow.
        These are recorded status counts, not inferred readiness or activity. Legacy get_projects.activeTaskCount
        continues to count all nonterminal tasks, including ideas. Unknown raw task statuses fall back to idea
        and are diagnosed. Project totals partition valid same-project milestone tasks, unassigned tasks and
        invalid milestone links. All captured milestones, including empty and terminal milestones, are included;
        unknown milestone statuses fall back to open and are diagnosed. Task counts do not infer milestone status.

        completionWindow is UTC [start,end): start is inclusive, end exclusive. Counts include currently done
        or abandoned tasks whose recorded completionDate lies in that window; they are not historical events.
        Terminal tasks missing completionDate are diagnosed and excluded from window counts. Nonterminal tasks
        are excluded even when a completionDate remains. Timestamps require seconds and an explicit Z or offset,
        with at most three fractional digits, valid calendar dates and start before end; no local/date-only values.

        lastRecordedActivity is the latest task creation/status change, comment creation or milestone creation/status
        change timestamp, with evidence kind and identity; ties use kind, UUID then physical identity. It is null
        without evidence. Arbitrary edits without an activity timestamp and orphan comments invent no activity.
        Unresolved project ownership is reported separately. Invalid links/statuses and identity collisions have
        exact diagnostic counts and at most ten deterministic identity samples per category, with sampleComplete.
        Names and display IDs never merge records. Ambiguous UUID attribution affecting scope fails explicitly.
        Summaries sort by normalized project name, UUID then physical identity; milestones sort by UUID then
        physical identity. Missing milestone display IDs remain absent.

        The payload contains projects, unresolvedProjects, diagnostics, completionWindow, nextCursor and expiresAt.
        Read evidence is outside text in _meta["me.nore.ig.transit/read"]: asOf, snapshotId, freshness and read.
        asOf is capture time, distinct from import evidence, completion window and expiry. readPolicy defaults to
        refresh_if_needed; cached skips refresh observation. Refresh observation lasts at most two seconds within
        the five-second read budget and considers a relevant import within thirty seconds recent; it does not
        force a pull. Freshness reports recent_import, stale, unknown or not_applicable and active/inactive sync;
        absent import proof stays unknown where applicable.

        Replay with snapshotId only returns the original first page. Continue with cursor only, optionally the
        identical original readPolicy. Both retain original scope, window, options, bytes and freshness metadata;
        they do not recapture or reassess freshness. Snapshots expire five minutes after capture completes,
        without extension; server stop/restart invalidates them. Expired/lost snapshots or cursors require a new
        initial request. Reusable cursors have a separate family from ordinary query_tasks cursors. A retained
        snapshot can also serve restricted query_tasks calls with captured descriptions/metadata and original
        comment-covered revisions, but without comment bodies. Live snapshots are not evicted to admit new ones.
        Retention admits at most eight reusable roots and sixteen MiB of logical encoded data; ordinary query
        retention has its own equal budget. These encoded budgets are not total heap-memory limits.

        The encoded read-only response is available to the transport within five seconds, including queueing,
        capture, aggregation and encoding. Each HTTP POST accepts one JSON-RPC object; JSON-RPC batch arrays
        are rejected. mutate_tasks can carry multiple application-level operations within one tools/call;
        it follows its own write and receipt contract. Eight unfinished physical reads can be admitted;
        timed-out work retains its slot until actually drained. Failures produce typed errors, never partial/empty
        success counts: INVALID_INPUT,
        PROJECT_NOT_FOUND, AMBIGUOUS_PROJECT, IDENTITY_AMBIGUITY, SNAPSHOT_INCOMPATIBLE, INVALID_SNAPSHOT,
        INVALID_CURSOR, QUERY_CAPACITY_EXCEEDED, READ_TIMEOUT or READ_BUSY. Required fetch, coherence and encoding
        failures carry storage_failure, incoherent_capture or serialization_failure read failure categories.
        No failed or expired request silently starts a replacement snapshot.
        """,
        inputSchema: JSONSchema(
            type: "object", properties: nil, required: nil,
            oneOf: initialSummarySchemas + [summaryReplaySchema, reusableContinuationSchema]
        )
    )

    /// Append only this initial branch to query_tasks; preserve its ordinary initial branch unchanged.
    static let snapshotTaskQueryInitialSchema = JSONSchema(
        type: "object",
        properties: [
            "snapshotId": uuid("Retained summary snapshot UUID; never capture a replacement implicitly."),
            "detailLevel": .stringEnum("Captured task detail level.", values: ["summary", "full"]),
            "includeComments": excludedComments,
            "limit": pageLimit("Required integer page size from 1 through 100, inclusive."),
            "projectId": uuid("Optional project UUID within the original captured scope; no scope expansion."),
            "status": .array(
                "Optional effective statuses; empty means unrestricted. Unknown stored statuses match idea.",
                enumValues: [
                    "idea", "planning", "spec", "ready-for-implementation", "in-progress",
                    "ready-for-review", "done", "abandoned"
                ]
            )
        ],
        required: ["snapshotId", "detailLevel", "includeComments", "limit"],
        additionalProperties: false
    )

    /// Shared query_tasks must replace/merge its cursor branch, not append an overlapping oneOf alternative.
    /// Its ordinary cursor family remains supported there; this fragment describes reusable cursors only.
    static let reusableContinuationSchema = JSONSchema(
        type: "object",
        properties: [
            "cursor": uuid("Opaque continuation cursor; expired or lost cursors require a new initial request."),
            "readPolicy": .stringEnum(
                "Optional identical original policy; omission retains it. No refresh or policy override.",
                values: ["cached", "refresh_if_needed"]
            )
        ],
        required: ["cursor"],
        additionalProperties: false
    )

    static let snapshotTaskQueryDescription = """
        Alternatively query a retained summary snapshot with snapshotId, detailLevel, includeComments:false and
        limit (integer 1...100). Only optional projectId and status are accepted; projectId must stay within the
        original scope. Status uses captured effective status, with unknown raw status treated as idea and
        exposed as storedStatus when different. An empty status array means unrestricted. Other filters, project
        names, comment bodies and a new readPolicy are incompatible. Rows sort by UUID then physical identity.
        Full detail uses captured description and metadata, retaining the original canonical comment-covered
        revision even though comment bodies are omitted. This does not alter ordinary stored-status query
        filtering, ordering or results. Continue with cursor and optionally the identical original readPolicy;
        retain the original snapshot, options, expiry and read metadata without live capture or refresh.
        Reusable cursor routing remains recognizable after expiry; failure never recaptures implicitly.
        """

    private static let summaryReplaySchema = JSONSchema(
        type: "object",
        properties: ["snapshotId": uuid("Replay the original first summary page and its frozen read metadata.")],
        required: ["snapshotId"],
        additionalProperties: false
    )

    private static var initialSummarySchemas: [JSONSchema] {
        let required = ["start", "end", "limit"]
        let properties: [String: JSONSchemaProperty] = [
            "start": timestamp("Inclusive completion-window start; explicit timezone, seconds; start < end."),
            "end": timestamp("Exclusive completion-window end; explicit timezone, seconds; start < end."),
            "limit": pageLimit("Required integer project page size from 1 through 100, inclusive."),
            "readPolicy": initialReadPolicy
        ]
        var byId = properties
        byId["projectId"] = uuid("Exact project UUID; exclusive with project name.")
        var byName = properties
        byName["project"] = .string("Nonempty normalized exact project name; exclusive with projectId.")
        return [
            JSONSchema(type: "object", properties: properties, required: required, additionalProperties: false),
            JSONSchema(type: "object", properties: byId, required: required + ["projectId"],
                       additionalProperties: false),
            JSONSchema(type: "object", properties: byName, required: required + ["project"],
                       additionalProperties: false)
        ]
    }

    private static var excludedComments: JSONSchemaProperty {
        var property = JSONSchemaProperty.boolean("Must be false; snapshot tasks never return comment bodies.")
        property.const = false
        return property
    }

    private static var initialReadPolicy: JSONSchemaProperty {
        var property = JSONSchemaProperty.stringEnum(
            "Default refresh_if_needed; cached skips import observation. Never guarantees remote completeness.",
            values: ["cached", "refresh_if_needed"]
        )
        property.defaultValue = "refresh_if_needed"
        return property
    }

    private static func pageLimit(_ description: String) -> JSONSchemaProperty {
        var property = JSONSchemaProperty.integer(description)
        property.minimum = 1
        property.maximum = 100
        return property
    }

    private static func uuid(_ description: String) -> JSONSchemaProperty {
        var property = JSONSchemaProperty.string(description)
        property.pattern = "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"
        return property
    }

    private static func timestamp(_ description: String) -> JSONSchemaProperty {
        var property = JSONSchemaProperty.string(description)
        property.pattern = #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}"#
            + #"(?:\.[0-9]{1,3})?(Z|[+-][0-9]{2}:[0-9]{2})$"#
        return property
    }
}
#endif
