import Foundation
import Darwin
import Synchronization

/// Process start is measured once; subsequent ages use a monotonic clock.
nonisolated enum MCPReadProcessClock {
    private static let anchor: (ContinuousClock.Instant, Double?) = {
        let now = ContinuousClock.now
        #if os(macOS)
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, &info, size) == size else { return (now, nil) }
        let start = Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000
        return (now, max(0, Date().timeIntervalSince1970 - start) * 1_000)
        #else
        return (now, nil)
        #endif
    }()

    static func uptimeMilliseconds() -> Double? {
        anchor.1.map { $0 + MCPReadTiming.seconds(anchor.0.duration(to: .now)) * 1_000 }
    }
}

nonisolated enum MCPReadFailureReason: String, Sendable { case deadline, cancellation, lifecycle, admission }

/// Fixed schema; no arguments, task identities, operation IDs, or captured contents.
nonisolated struct MCPReadFailureSnapshot: Codable, Sendable {
    let observedAt: Date
    let reason: String
    let tool: String
    let phase: String
    let outcome: String
    let generation: UInt64
    let processUptimeMs: Double?
    let phaseAgeMs: Double
    let oldestWorkerAgeMs: Double
    let physicalCount: Int
    var droppedEvents: UInt64 = 0

    private static let knownTools = ["query_tasks", "query_milestones", "get_projects", "query_project_summaries",
                                     "preview_task_consolidation", "preview_task_consolidation_undo",
                                     "native_consolidation_history", "historical_batch"]

    var hasSafeSchema: Bool {
        (Self.knownTools.contains(tool) || tool == "unknown")
            && ["queue", "validation", "refresh", "capture", "transform", "serialization", "aggregation",
                "terminal", "physicalFinish", "discard"].contains(phase)
            && ["timeout", "busy"].contains(outcome)
            && MCPReadFailureReason(rawValue: reason) != nil
            && phaseAgeMs.isFinite && phaseAgeMs >= 0
            && oldestWorkerAgeMs.isFinite && oldestWorkerAgeMs >= 0
            && (0...8).contains(physicalCount)
            && (processUptimeMs.map { $0.isFinite && $0 >= 0 } ?? true)
    }

    init(tool: String, phase: MCPReadDiagnosticPhase, outcome: MCPReadDiagnosticOutcome,
         generation: UInt64, reason: MCPReadFailureReason = .deadline, processUptimeMs: Double?, phaseAgeMs: Double,
         oldestWorkerAgeMs: Double, physicalCount: Int) {
        self.observedAt = Date()
        self.reason = reason.rawValue
        self.tool = Self.knownTools.contains(tool) ? tool : "unknown"
        self.phase = String(describing: phase)
        self.outcome = String(describing: outcome)
        self.generation = generation
        self.processUptimeMs = processUptimeMs
        self.phaseAgeMs = max(0, phaseAgeMs)
        self.oldestWorkerAgeMs = max(0, oldestWorkerAgeMs)
        self.physicalCount = physicalCount
    }
}

/// Only the diagnostic writer queue accesses this journal. Two fixed bounds also
/// cover previous-process input before decoding; corrupt/oversized input is retired.
nonisolated final class MCPReadFailureJournal: Sendable {
    static let recordLimit = 64
    static let byteLimit = 64 * 1_024
    private let url: URL
    private let state = Mutex<[MCPReadFailureSnapshot]?>(nil)

    init(url: URL) { self.url = url }

    private func readBoundedInput() -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.byteLimit + 1), data.count <= Self.byteLimit else {
            return nil
        }
        return data
    }

    func append(_ value: MCPReadFailureSnapshot) throws {
        try state.withLock { records in
            if records == nil {
                records = []
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   size <= Self.byteLimit, let data = readBoundedInput(),
                   let previous = try? JSONDecoder().decode([MCPReadFailureSnapshot].self, from: data),
                   previous.allSatisfy(\.hasSafeSchema) {
                    records = Array(previous.suffix(Self.recordLimit))
                }
            }
            var next = Array((records ?? []).suffix(Self.recordLimit - 1))
            next.append(value)
            let data = try JSONEncoder().encode(next)
            guard data.count <= Self.byteLimit else { throw CocoaError(.fileWriteOutOfSpace) }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                   withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            records = next
        }
    }
}
