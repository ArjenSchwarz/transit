#if os(macOS)
import Foundation

/// Own value-only wire encoding. No live data, freshness assessment or publication occurs here.
nonisolated enum MCPPortfolioReadEncoding {
    static let byteLimit = 16 * 1024 * 1024

    static func check(_ operation: MCPReadOperation) throws {
        guard operation.shouldContinue(), !Task.isCancelled else {
            throw MCPTaskQueryError(code: "READ_TIMEOUT", message: "Read exceeded its original admission budget")
        }
    }

    static func publicationDeadline(_ operation: MCPReadOperation) throws -> ContinuousClock.Instant {
        try check(operation)
        // Sampling before remainingBudget produces a conservative original cutoff, not a restarted timer.
        let now = ContinuousClock.now
        let remaining = operation.remainingBudget()
        guard remaining > .zero else {
            throw MCPTaskQueryError(code: "READ_TIMEOUT", message: "Read exceeded its original admission budget")
        }
        return now.advanced(by: remaining)
    }

    static func instant(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func expiry(_ view: CapturedReadView) throws -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let asOf = formatter.date(from: view.metadata.asOf) else { throw MCPReadCaptureError.incoherentCapture }
        let duration = view.createdAt.duration(to: view.retentionDeadline).components
        return instant(asOf.addingTimeInterval(Double(duration.seconds) + Double(duration.attoseconds) / 1e18))
    }

    static func encode(_ value: Any) throws -> Data {
        do { return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) } catch {
            throw MCPReadCaptureError.serializationFailure
        }
    }

    static func prepared(_ bytes: Data, metadata: Data) throws -> MCPPreparedToolRead {
        guard let text = String(data: bytes, encoding: .utf8) else { throw MCPReadCaptureError.serializationFailure }
        let prepared = try MCPPreparedToolRead(text: text, frozenMetadataBytes: metadata)
        guard prepared.encodedToolResult.count <= byteLimit else { throw PublicationRejection.capacity }
        return prepared
    }

    static func normalized(_ error: Error, cursor: Bool) throws -> MCPPreparedToolRead? {
        let code: String
        let message: String
        if let retained = retentionFault(error, cursor: cursor) {
            code = retained.code; message = retained.message
        } else {
            switch error {
            case MCPReusableSnapshotError.incompatible, MCPSnapshotTaskQueryError.incompatible:
                code = "SNAPSHOT_INCOMPATIBLE"; message = "Request is incompatible with the retained view"
            case PortfolioSummaryError.identityAmbiguity:
                code = "IDENTITY_AMBIGUITY"; message = "Captured identities are ambiguous in the requested scope"
            case PortfolioSummaryError.incoherentCapture: throw MCPReadCaptureError.incoherentCapture
            case CompletionWindowError.invalidInput, MCPSnapshotTaskQueryError.invalidInput:
                code = "INVALID_INPUT"; message = "Invalid captured-read arguments"
            case MCPSnapshotTaskQueryError.invalidCursor:
                code = "INVALID_CURSOR"; message = "Invalid reusable cursor"
            case let error as MCPPortfolioRequestError: code = error.code; message = error.message
            case let error as MCPTaskQueryError: code = error.code; message = error.message
            default: return nil
            }
        }
        guard let text = String(data: try encode(["error": ["code": code, "message": message]]), encoding: .utf8) else {
            throw MCPReadCaptureError.serializationFailure
        }
        return try MCPPreparedToolRead(text: text, isError: true)
    }

    private static func retentionFault(_ error: Error, cursor: Bool) -> (code: String, message: String)? {
        switch error {
        case PublicationRejection.capacity: return ("QUERY_CAPACITY_EXCEEDED", "Captured read capacity exceeded")
        case PublicationRejection.busy: return ("READ_BUSY", "Read publication changed; retry the request")
        case PublicationRejection.expired:
            return (cursor ? "INVALID_CURSOR" : "INVALID_SNAPSHOT", "Retained view expired; start a new summary")
        case MCPReusableSnapshotError.invalidSnapshot:
            return ("INVALID_SNAPSHOT", "Unknown or expired snapshot; start a new summary")
        case MCPReusableSnapshotError.invalidCursor:
            return ("INVALID_CURSOR", "Unknown or expired cursor; start a new summary")
        default: return nil
        }
    }

    static func cursor() -> String {
        var bytes = UUID().uuid
        bytes.6 = (bytes.6 & 0x0F) | 0x80
        bytes.8 = (bytes.8 & 0x3F) | 0x80
        return UUID(uuid: bytes).uuidString
    }

    static func summaryPages(_ summary: PortfolioSummary, view: CapturedReadView, limit: Int,
                             operation: MCPReadOperation) throws -> (pages: [Data], cursors: [String]) {
        guard (1...100).contains(limit) else { throw CompletionWindowError.invalidInput }
        let count = max(1, (summary.projects.count + limit - 1) / limit)
        var allocated: Set<String> = [view.metadata.snapshotId]
        let cursors = (0..<(count - 1)).map { _ -> String in
            var token = cursor()
            while !allocated.insert(token).inserted { token = cursor() }
            return token
        }
        let window = ["start": instant(summary.completionWindow.start), "end": instant(summary.completionWindow.end)]
        let expiresAt = try expiry(view)
        var pages: [Data] = []
        var byteCount = 0
        for position in 0..<count {
            try check(operation)
            let start = position * limit
            let end = min(start + limit, summary.projects.count)
            let next: Any = position < cursors.count ? cursors[position] : NSNull()
            let bytes = try encode([
                "projects": summary.projects[start..<end].map(project),
                "unresolvedProjects": breakdown(summary.unresolvedProjects),
                "diagnostics": summary.diagnostics.map(diagnostic), "completionWindow": window,
                "nextCursor": next, "expiresAt": expiresAt
            ])
            byteCount += bytes.count
            guard byteCount <= byteLimit else { throw PublicationRejection.capacity }
            pages.append(bytes)
        }
        return (pages, cursors)
    }
}

extension MCPPortfolioReadEncoding {
    nonisolated private static func counts(_ value: PortfolioStatusCounts) -> [String: Int] {
        ["idea": value.idea, "planning": value.planning, "spec": value.spec,
         "ready-for-implementation": value.readyForImplementation, "in-progress": value.inProgress,
         "ready-for-review": value.readyForReview, "done": value.done, "abandoned": value.abandoned]
    }
    nonisolated private static func recent(_ value: PortfolioRecentCompletions) -> [String: Int] {
        ["done": value.done, "abandoned": value.abandoned,
         "missingCompletionDateCount": value.missingCompletionDateCount]
    }
    nonisolated private static func breakdown(_ value: PortfolioTaskBreakdown) -> [String: Any] {
        ["countsByStatus": counts(value.countsByStatus), "totalTaskCount": value.totalTaskCount,
         "recentCompletions": recent(value.recentCompletions)]
    }
    nonisolated private static func diagnostic(_ value: PortfolioDiagnostic) -> [String: Any] {
        ["category": value.category, "affectedCount": value.affectedCount, "sampleComplete": value.sampleComplete,
         "samples": value.samples.map { sample in
             ["entityKind": sample.entityKind, "id": sample.id.uuidString,
              "displayId": sample.displayId as Any? ?? NSNull(),
              "discriminator": sample.discriminator as Any? ?? NSNull()] as [String: Any]
         }]
    }
    nonisolated private static func milestone(_ value: PortfolioMilestoneSummary) -> [String: Any] {
        ["milestoneId": value.milestoneId.uuidString, "displayId": value.displayId as Any? ?? NSNull(),
         "name": value.name, "rawStatus": value.rawStatus, "status": value.status, "invalidStatus": value.invalidStatus,
         "countsByStatus": counts(value.countsByStatus), "totalTaskCount": value.totalTaskCount,
         "recentCompletions": recent(value.recentCompletions)]
    }
    nonisolated private static func project(_ value: PortfolioProjectSummary) -> [String: Any] {
        let activity: Any
        if let evidence = value.lastRecordedActivity {
            activity = ["timestamp": instant(evidence.timestamp), "kind": evidence.kind.rawValue,
                        "id": evidence.id.uuidString]
        } else { activity = NSNull() }
        return ["projectId": value.projectId.uuidString, "name": value.name,
                "countsByStatus": counts(value.countsByStatus), "totalTaskCount": value.totalTaskCount,
                "ideaCount": value.ideaCount, "inProgressCount": value.inProgressCount,
                "workflowTaskCount": value.workflowTaskCount, "nonterminalTaskCount": value.nonterminalTaskCount,
                "recentCompletions": recent(value.recentCompletions), "lastRecordedActivity": activity,
                "milestones": value.milestones.map(milestone),
                "unassignedMilestone": breakdown(value.unassignedMilestone),
                "invalidMilestoneAssociations": breakdown(value.invalidMilestoneAssociations),
                "diagnostics": value.diagnostics.map(diagnostic)]
    }
}
#endif
