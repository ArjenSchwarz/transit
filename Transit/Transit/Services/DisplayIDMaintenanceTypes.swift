import Foundation

// MARK: - Failure Codes

/// String-raw-valued failure codes shared between scan/reassign reports.
/// Raw strings match the JSON `failure.code` and `warning` field values.
enum FailureCode: String, Codable, Sendable {
    case allocationFailed = "allocation-failed"
    case saveFailed = "save-failed"
    case staleId = "stale-id"
    case commentFailed = "comment-failed"
    case counterAdvanceFailed = "counter-advance-failed"
}

// MARK: - DuplicateReport

/// Top-level report of duplicate display IDs across tasks and milestones.
struct DuplicateReport: Codable, Sendable {
    let tasks: [DuplicateGroup]
    let milestones: [DuplicateGroup]
}

/// A set of records sharing the same `permanentDisplayId`. Records are ordered
/// winner-first followed by losers in winner-selection order.
struct DuplicateGroup: Codable, Sendable {
    let displayId: Int
    let records: [RecordRef]
}

/// A record's identity payload included in the duplicate report.
/// `role` is emitted alongside winner-first ordering so consumers can re-sort.
struct RecordRef: Codable, Sendable {
    let id: UUID
    let name: String
    let projectName: String
    let creationDate: Date
    let role: RecordRole

    enum CodingKeys: String, CodingKey {
        case id, name, projectName, creationDate, role
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(projectName, forKey: .projectName)
        try container.encode(Self.dateFormatter.string(from: creationDate), forKey: .creationDate)
        try container.encode(role, forKey: .role)
    }

    init(id: UUID, name: String, projectName: String, creationDate: Date, role: RecordRole) {
        self.id = id
        self.name = name
        self.projectName = projectName
        self.creationDate = creationDate
        self.role = role
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let idString = try container.decode(String.self, forKey: .id)
        guard let parsedId = UUID(uuidString: idString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: container, debugDescription: "Invalid UUID string"
            )
        }
        self.id = parsedId
        self.name = try container.decode(String.self, forKey: .name)
        self.projectName = try container.decode(String.self, forKey: .projectName)
        let dateString = try container.decode(String.self, forKey: .creationDate)
        self.creationDate = Self.dateFormatter.date(from: dateString) ?? Date()
        self.role = try container.decode(RecordRole.self, forKey: .role)
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter
    }()
}

enum RecordRole: String, Codable, Sendable {
    case winner
    case loser
}

// MARK: - ReassignmentResult

enum ReassignmentStatus: String, Codable, Sendable {
    // swiftlint:disable:next identifier_name
    case ok
    case busy
}

/// Top-level result of a reassignment run. `counterAdvance` is always a key
/// in the envelope; value is `null` for the busy variant, a non-null object
/// otherwise.
struct ReassignmentResult: Codable, Sendable {
    let status: ReassignmentStatus
    let groups: [GroupResult]
    let counterAdvance: CounterAdvanceResult?

    /// Convenience for the single-flight "another run is in progress" return.
    static var busy: ReassignmentResult {
        ReassignmentResult(status: .busy, groups: [], counterAdvance: nil)
    }

    init(
        status: ReassignmentStatus,
        groups: [GroupResult],
        counterAdvance: CounterAdvanceResult?
    ) {
        self.status = status
        self.groups = groups
        self.counterAdvance = counterAdvance
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(groups, forKey: .groups)
        // Always emit counterAdvance key (nullable) per design.
        try container.encode(counterAdvance, forKey: .counterAdvance)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try container.decode(ReassignmentStatus.self, forKey: .status)
        self.groups = try container.decode([GroupResult].self, forKey: .groups)
        self.counterAdvance = try container.decodeIfPresent(CounterAdvanceResult.self, forKey: .counterAdvance)
    }

    enum CodingKeys: String, CodingKey { case status, groups, counterAdvance }
}

enum RecordType: String, Codable, Sendable {
    case task
    case milestone
}

struct GroupResult: Codable, Sendable {
    let type: RecordType
    let displayId: Int
    let winner: GroupResultWinner
    let reassignments: [ReassignmentEntry]
    let failure: GroupFailure?

    /// Stable identifier for SwiftUI diffing across mixed task/milestone lists.
    /// Plain `displayId` collides between e.g. T-5 and M-5.
    var stableID: String { "\(type.rawValue)-\(displayId)" }

    init(
        type: RecordType,
        displayId: Int,
        winner: GroupResultWinner,
        reassignments: [ReassignmentEntry],
        failure: GroupFailure?
    ) {
        self.type = type
        self.displayId = displayId
        self.winner = winner
        self.reassignments = reassignments
        self.failure = failure
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(displayId, forKey: .displayId)
        try container.encode(winner, forKey: .winner)
        try container.encode(reassignments, forKey: .reassignments)
        // Always emit failure key (nullable).
        try container.encode(failure, forKey: .failure)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(RecordType.self, forKey: .type)
        self.displayId = try container.decode(Int.self, forKey: .displayId)
        self.winner = try container.decode(GroupResultWinner.self, forKey: .winner)
        self.reassignments = try container.decode([ReassignmentEntry].self, forKey: .reassignments)
        self.failure = try container.decodeIfPresent(GroupFailure.self, forKey: .failure)
    }

    enum CodingKeys: String, CodingKey {
        case type, displayId, winner, reassignments, failure
    }
}

struct GroupResultWinner: Codable, Sendable {
    let id: UUID
    let name: String

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(name, forKey: .name)
    }

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let idString = try container.decode(String.self, forKey: .id)
        guard let parsedId = UUID(uuidString: idString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: container, debugDescription: "Invalid UUID string"
            )
        }
        self.id = parsedId
        self.name = try container.decode(String.self, forKey: .name)
    }

    enum CodingKeys: String, CodingKey { case id, name }
}

struct ReassignmentEntry: Codable, Sendable {
    let id: UUID
    let name: String
    let previousDisplayId: Int
    let newDisplayId: Int
    let commentWarning: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(previousDisplayId, forKey: .previousDisplayId)
        try container.encode(newDisplayId, forKey: .newDisplayId)
        // Always emit commentWarning key (nullable)
        try container.encode(commentWarning, forKey: .commentWarning)
    }

    init(id: UUID, name: String, previousDisplayId: Int, newDisplayId: Int, commentWarning: String?) {
        self.id = id
        self.name = name
        self.previousDisplayId = previousDisplayId
        self.newDisplayId = newDisplayId
        self.commentWarning = commentWarning
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let idString = try container.decode(String.self, forKey: .id)
        guard let parsedId = UUID(uuidString: idString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: container, debugDescription: "Invalid UUID string"
            )
        }
        self.id = parsedId
        self.name = try container.decode(String.self, forKey: .name)
        self.previousDisplayId = try container.decode(Int.self, forKey: .previousDisplayId)
        self.newDisplayId = try container.decode(Int.self, forKey: .newDisplayId)
        self.commentWarning = try container.decodeIfPresent(String.self, forKey: .commentWarning)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, previousDisplayId, newDisplayId, commentWarning
    }
}

struct GroupFailure: Codable, Sendable {
    let code: FailureCode
    let message: String
}

// MARK: - Counter Advance

struct CounterAdvanceResult: Codable, Sendable {
    let task: CounterAdvanceEntry?
    let milestone: CounterAdvanceEntry?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Always emit both keys (nullable) per design.
        try container.encode(task, forKey: .task)
        try container.encode(milestone, forKey: .milestone)
    }

    init(task: CounterAdvanceEntry?, milestone: CounterAdvanceEntry?) {
        self.task = task
        self.milestone = milestone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.task = try container.decodeIfPresent(CounterAdvanceEntry.self, forKey: .task)
        self.milestone = try container.decodeIfPresent(CounterAdvanceEntry.self, forKey: .milestone)
    }

    enum CodingKeys: String, CodingKey { case task, milestone }
}

struct CounterAdvanceEntry: Codable, Sendable {
    let advancedTo: Int?
    let warning: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Always emit both keys (nullable).
        try container.encode(advancedTo, forKey: .advancedTo)
        try container.encode(warning, forKey: .warning)
    }

    init(advancedTo: Int?, warning: String?) {
        self.advancedTo = advancedTo
        self.warning = warning
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.advancedTo = try container.decodeIfPresent(Int.self, forKey: .advancedTo)
        self.warning = try container.decodeIfPresent(String.self, forKey: .warning)
    }

    enum CodingKeys: String, CodingKey { case advancedTo, warning }
}
