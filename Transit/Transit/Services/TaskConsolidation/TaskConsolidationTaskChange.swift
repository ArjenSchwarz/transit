import Foundation

/// Full fields belong only to the transient reviewed input, never saved history.
nonisolated struct TaskConsolidationReviewedTaskChange: Codable, Equatable, Sendable {
    let taskId: UUID
    let before: TaskConsolidationRawFields
    let after: TaskConsolidationRawFields

    var delta: TaskConsolidationTaskChange { .init(taskId: taskId, before: before, after: after) }
}

/// A present field contains both values, including explicit JSON null. Omission
/// means that the operation did not change that field.
nonisolated struct TaskConsolidationFieldDelta: Codable, Equatable, Sendable {
    let before: String?
    let after: String?

    init(before: String?, after: String?) {
        self.before = before
        self.after = after
    }

    private enum CodingKeys: String, CodingKey { case before, after }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard values.contains(.before), values.contains(.after) else {
            throw TaskConsolidationHistoryError.malformed
        }
        before = try values.decodeIfPresent(String.self, forKey: .before)
        after = try values.decodeIfPresent(String.self, forKey: .after)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        if let before { try values.encode(before, forKey: .before) } else { try values.encodeNil(forKey: .before) }
        if let after { try values.encode(after, forKey: .after) } else { try values.encodeNil(forKey: .after) }
    }

    var inverse: Self { .init(before: after, after: before) }
}

nonisolated struct TaskConsolidationTaskChange: Codable, Equatable, Sendable {
    let taskId: UUID
    let fields: [String: TaskConsolidationFieldDelta]

    init(taskId: UUID, before: TaskConsolidationRawFields, after: TaskConsolidationRawFields) {
        self.taskId = taskId
        let values: [(String, TaskConsolidationFieldDelta)] = [
            ("description", .init(before: before.description, after: after.description)),
            ("metadataJSON", .init(before: before.metadataJSON, after: after.metadataJSON)),
            ("statusRawValue", .init(before: before.statusRawValue, after: after.statusRawValue)),
            ("lastStatusChangeDate", .init(before: before.lastStatusChangeDate, after: after.lastStatusChangeDate)),
            ("completionDate", .init(before: before.completionDate, after: after.completionDate))
        ]
        fields = Dictionary(uniqueKeysWithValues: values.compactMap { key, delta in
            delta.before == delta.after ? nil : (key, delta)
        })
    }

    private init(taskId: UUID, fields: [String: TaskConsolidationFieldDelta]) {
        self.taskId = taskId
        self.fields = fields
    }

    var inverse: Self { .init(taskId: taskId, fields: fields.mapValues(\.inverse)) }

    func validate() throws {
        guard !fields.isEmpty else { throw TaskConsolidationHistoryError.malformed }
        for (field, delta) in fields {
            guard delta.before != delta.after else { throw TaskConsolidationHistoryError.malformed }
            for value in [delta.before, delta.after] { try Self.validate(value, field: field) }
        }
    }

    private static func validate(_ value: String?, field: String) throws {
        switch field {
        case "description": break
        case "metadataJSON": try validateMetadata(value)
        case "statusRawValue":
            guard let value, TaskStatus(rawValue: value) != nil else { throw TaskConsolidationHistoryError.malformed }
        case "lastStatusChangeDate":
            guard let value else { throw TaskConsolidationHistoryError.malformed }
            _ = try TaskConsolidationRawFields.date(value)
        case "completionDate":
            if let value { _ = try TaskConsolidationRawFields.date(value) }
        default: throw TaskConsolidationHistoryError.malformed
        }
    }

    private static func validateMetadata(_ value: String?) throws {
        if let value {
            guard (try JSONSerialization.jsonObject(with: Data(value.utf8))) is [String: String] else {
                throw TaskConsolidationHistoryError.malformed
            }
        }
    }

}
