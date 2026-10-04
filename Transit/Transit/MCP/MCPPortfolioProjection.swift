#if os(macOS)
import Foundation

/// Private page plan; the shared response gate stages its continuation bytes before publication.
nonisolated struct EncodedSnapshotTaskPages: Sendable {
    let firstPage: Data
    let pages: [Data]
    let cursors: [String]
    let frozenMetadataBytes: Data
    let snapshotId: String
    let retentionDeadline: ContinuousClock.Instant
}

nonisolated enum MCPPortfolioProjection {
    private static let summaryKeys: Set<String> = [
        "taskId", "name", "status", "type", "priority", "lastStatusChangeDate",
        "displayId", "projectId", "projectName", "completionDate", "milestone"
    ]

    static func query(root: RetainedView, request: MCPSnapshotTaskQueryRequest) throws -> EncodedSnapshotTaskPages {
        try Task.checkCancellation()
        guard case .initial(let snapshotID, let detail, let limit, let projectID, let statuses) = request,
              root.capture.completeness == .completePortfolio, root.capture.captureScope != .selectedQuery else {
            throw MCPReusableSnapshotError.incompatible
        }
        guard snapshotID == root.capture.metadata.snapshotId else { throw MCPReusableSnapshotError.invalidSnapshot }
        guard (1...100).contains(limit),
              statuses.allSatisfy({ MCPSnapshotTaskQueryRequest.supportedStatuses.contains($0) }) else {
            throw MCPSnapshotTaskQueryError.invalidInput
        }
        let records = try selectedTasks(view: root.capture, projectID: projectID)
        let filtered = statuses.isEmpty ? records : records.filter { statuses.contains(effectiveStatus($0)) }
        let ordered = filtered.sorted {
            ($0.id.uuidString, $0.physicalKey.encodedIdentifier.base64EncodedString())
                < ($1.id.uuidString, $1.physicalKey.encodedIdentifier.base64EncodedString())
        }
        var rows: [[String: Any]] = []
        for (position, record) in ordered.enumerated() {
            if position.isMultiple(of: 256) { try Task.checkCancellation() }
            rows.append(try dictionary(task(record: record, detail: detail).json))
        }
        let encoded = try encodePages(rows, limit: limit, root: root)
        return EncodedSnapshotTaskPages(
            firstPage: encoded.pages[0], pages: Array(encoded.pages.dropFirst()), cursors: encoded.cursors,
            frozenMetadataBytes: root.frozenMetadataBytes, snapshotId: snapshotID,
            retentionDeadline: root.capture.retentionDeadline)
    }

    static func task(record: ReadTask, detail: SnapshotTaskDetail) throws -> EncodedTaskRecord {
        // Decode the retained canonical body; never mint an r1 from a derived status or hidden comments.
        guard let captured = record.fullRecordWithoutCommentsJSON, let revision = record.revision else {
            throw PortfolioSummaryError.incoherentCapture
        }
        var output = try dictionary(captured)
        if detail == .summary { output = output.filter { summaryKeys.contains($0.key) } }
        output.removeValue(forKey: "comments")
        output.removeValue(forKey: "commentKeys")
        output.removeValue(forKey: "storedStatus")
        let status = effectiveStatus(record)
        output["status"] = status
        if status != record.rawStatus { output["storedStatus"] = record.rawStatus }
        if detail == .full { output["revision"] = revision }
        return EncodedTaskRecord(json: try encode(output))
    }

    private static func effectiveStatus(_ task: ReadTask) -> String {
        MCPSnapshotTaskQueryRequest.supportedStatuses.contains(task.rawStatus) ? task.rawStatus : "idea"
    }

    private static func selectedTasks(view: CapturedReadView, projectID: UUID?) throws -> [ReadTask] {
        var projectKeys: Set<LocalRecordKey>
        switch view.captureScope {
        case .wholePortfolio: projectKeys = Set(view.projects.map(\.physicalKey))
        case .projects(let keys):
            projectKeys = Set(keys)
            guard !keys.isEmpty, projectKeys.count == keys.count,
                  keys.allSatisfy({ key in view.projects.contains { $0.physicalKey == key } }) else {
                throw MCPReusableSnapshotError.incompatible
            }
        case .selectedQuery: throw MCPReusableSnapshotError.incompatible
        }
        if let projectID {
            let matching = view.projects.filter { $0.id == projectID }
            let permitted = matching.filter { projectKeys.contains($0.physicalKey) }
            guard !permitted.isEmpty else { throw MCPReusableSnapshotError.incompatible }
            guard matching.count == 1 else { throw PortfolioSummaryError.identityAmbiguity }
            projectKeys = Set(permitted.map(\.physicalKey))
        }
        let includeOrphans = view.captureScope == .wholePortfolio && projectID == nil
        let tasks = view.tasks.filter {
            includeOrphans || $0.projectKey.map { projectKeys.contains($0) } == true
        }
        let milestones = view.milestones.filter { $0.projectKey.map { projectKeys.contains($0) } == true }
        // Reuse T-2382 attribution rules before status filtering. Generic canonical capture
        // validation remains the shared provider's responsibility at handler admission.
        try PortfolioSummaryService.validateIdentities(
            view: view, projects: projectKeys, tasks: tasks, milestones: milestones)
        return tasks
    }

    private static func encodePages(_ rows: [[String: Any]], limit: Int, root: RetainedView) throws
        -> (pages: [Data], cursors: [String]) {
        let count = max(1, (rows.count + limit - 1) / limit)
        var allocated: Set<String> = [root.capture.metadata.snapshotId]
        let cursors = (0..<(count - 1)).map { _ -> String in
            var cursor = reusableCursor()
            while !allocated.insert(cursor).inserted { cursor = reusableCursor() }
            return cursor
        }
        let expiry = try expiryText(root)
        var pages: [Data] = []
        var byteCount = 0
        for position in 0..<count {
            try Task.checkCancellation()
            let start = position * limit
            let end = min(start + limit, rows.count)
            let next: Any = position < cursors.count ? cursors[position] : NSNull()
            let page = try encode(["results": Array(rows[start..<end]), "nextCursor": next, "expiresAt": expiry])
            byteCount += page.count
            guard byteCount <= 16 * 1024 * 1024 else { throw PublicationRejection.capacity }
            pages.append(page)
        }
        return (pages, cursors)
    }

    private static func reusableCursor() -> String {
        var bytes = UUID().uuid
        bytes.6 = (bytes.6 & 0x0F) | 0x80
        bytes.8 = (bytes.8 & 0x3F) | 0x80
        return UUID(uuid: bytes).uuidString
    }

    private static func expiryText(_ root: RetainedView) throws -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let capturedAt = formatter.date(from: root.capture.metadata.asOf) else {
            throw PortfolioSummaryError.incoherentCapture
        }
        let duration = root.capture.createdAt.duration(to: root.capture.retentionDeadline).components
        let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        return formatter.string(from: capturedAt.addingTimeInterval(seconds))
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        do {
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MCPReadCaptureError.serializationFailure
            }
            return result
        } catch { throw MCPReadCaptureError.serializationFailure }
    }

    private static func encode(_ dictionary: [String: Any]) throws -> Data {
        do { return try JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]) } catch {
            throw MCPReadCaptureError.serializationFailure
        }
    }
}
#endif
