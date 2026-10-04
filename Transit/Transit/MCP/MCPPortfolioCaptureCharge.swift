#if os(macOS)
import Foundation

/// Logical encoded backing-view bytes, including typed identity/activity evidence and opaque metadata.
/// This is a retention charge, not a heap-memory estimate.
nonisolated enum MCPPortfolioCaptureCharge {
    static func bytes(_ capsule: MCPPreparedReadCapture, operation: MCPReadOperation) throws -> Int {
        let view = capsule.view
        var scope: [String: Any] = ["kind": "wholePortfolio"]
        if case .projects(let keys) = view.captureScope { scope = ["kind": "projects", "keys": keys.map(key)] }
        let duration = view.createdAt.duration(to: view.retentionDeadline).components
        var count = try MCPPortfolioReadEncoding.encode([
            "scope": scope, "completeness": "completePortfolio", "createdAtOffset": 0,
            "retentionSeconds": duration.seconds, "retentionAttoseconds": duration.attoseconds,
            "projects": [], "tasks": [], "milestones": [], "comments": [], "frozenMetadata": NSNull()
        ]).count
        try add(capsule.frozenMetadataBytes.count, to: &count)
        try records(view.projects, operation: operation, count: &count, encode: project)
        try records(view.tasks, operation: operation, count: &count, encode: task)
        try records(view.milestones, operation: operation, count: &count, encode: milestone)
        try records(view.comments, operation: operation, count: &count, encode: comment)
        return count
    }

    private static func add(_ bytes: Int, to count: inout Int) throws {
        let (sum, overflow) = count.addingReportingOverflow(bytes)
        guard !overflow, sum <= MCPPortfolioReadEncoding.byteLimit else { throw PublicationRejection.capacity }
        count = sum
    }

    private static func records<Record>(
        _ values: [Record], operation: MCPReadOperation, count: inout Int,
        encode: (Record) -> [String: Any]
    ) throws {
        // Each array's syntax and element separators are charged alongside its records.
        try add(2 + values.count, to: &count)
        for (position, value) in values.enumerated() {
            if position.isMultiple(of: 256) { try MCPPortfolioReadEncoding.check(operation) }
            try add(MCPPortfolioReadEncoding.encode(encode(value)).count, to: &count)
        }
    }

    private static func key(_ value: LocalRecordKey) -> String { value.encodedIdentifier.base64EncodedString() }
    private static func optionalKey(_ value: LocalRecordKey?) -> Any { value.map(key) as Any? ?? NSNull() }
    private static func optionalID(_ value: UUID?) -> Any { value.map(\.uuidString) as Any? ?? NSNull() }
    private static func optionalBytes(_ value: Data?) -> Any { value?.base64EncodedString() as Any? ?? NSNull() }
    private static func optionalDate(_ value: Date?) -> Any {
        value.map(\.timeIntervalSinceReferenceDate) as Any? ?? NSNull()
    }

    private static func project(_ value: ReadProject) -> [String: Any] {
        ["physicalKey": key(value.physicalKey), "id": value.id.uuidString, "name": value.name,
         "description": value.projectDescription, "gitRepo": value.gitRepo as Any? ?? NSNull(),
         "colorHex": value.colorHex, "taskKeys": value.taskKeys.map(key), "milestoneKeys": value.milestoneKeys.map(key),
         "selectedRecordJSON": value.selectedRecordJSON.base64EncodedString()]
    }

    private static func task(_ value: ReadTask) -> [String: Any] {
        ["physicalKey": key(value.physicalKey), "id": value.id.uuidString,
         "displayId": value.permanentDisplayId as Any? ?? NSNull(), "name": value.name,
         "description": value.taskDescription as Any? ?? NSNull(),
         "projectKey": optionalKey(value.projectKey), "milestoneKey": optionalKey(value.milestoneKey),
         "storedProjectID": optionalID(value.storedProjectID), "storedMilestoneID": optionalID(value.storedMilestoneID),
         "rawStatus": value.rawStatus, "effectiveStatus": value.effectiveStatus,
         "rawType": value.rawType, "effectiveType": value.effectiveType,
         "rawPriority": value.rawPriority, "effectivePriority": value.effectivePriority,
         "metadata": value.metadata, "metadataJSON": value.metadataJSON as Any? ?? NSNull(),
         "creationDate": value.creationDate.timeIntervalSinceReferenceDate,
         "lastStatusChangeDate": value.lastStatusChangeDate.timeIntervalSinceReferenceDate,
         "completionDate": optionalDate(value.completionDate), "commentKeys": value.commentKeys.map(key),
         "selectedRecordJSON": value.selectedRecordJSON.base64EncodedString(),
         "revision": value.revision as Any? ?? NSNull(),
         "fullRecordWithoutCommentsJSON": optionalBytes(value.fullRecordWithoutCommentsJSON),
         "requestedCommentRecordsJSON": optionalBytes(value.requestedCommentRecordsJSON)]
    }

    private static func milestone(_ value: ReadMilestone) -> [String: Any] {
        ["physicalKey": key(value.physicalKey), "id": value.id.uuidString,
         "displayId": value.permanentDisplayId as Any? ?? NSNull(), "name": value.name,
         "description": value.milestoneDescription as Any? ?? NSNull(), "projectKey": optionalKey(value.projectKey),
         "storedProjectID": optionalID(value.storedProjectID), "rawStatus": value.rawStatus,
         "effectiveStatus": value.effectiveStatus, "creationDate": value.creationDate.timeIntervalSinceReferenceDate,
         "lastStatusChangeDate": value.lastStatusChangeDate.timeIntervalSinceReferenceDate,
         "completionDate": optionalDate(value.completionDate), "taskKeys": value.taskKeys.map(key),
         "selectedRecordJSON": value.selectedRecordJSON.base64EncodedString()]
    }

    private static func comment(_ value: ReadCommentEvidence) -> [String: Any] {
        ["physicalKey": key(value.physicalKey), "id": value.id.uuidString, "taskKey": optionalKey(value.taskKey),
         "storedTaskID": optionalID(value.storedTaskID),
         "creationDate": value.creationDate.timeIntervalSinceReferenceDate,
         "content": value.content, "authorName": value.authorName, "isAgent": value.isAgent,
         "selectedRecordJSON": value.selectedRecordJSON.base64EncodedString()]
    }
}
#endif
