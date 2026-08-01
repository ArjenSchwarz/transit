import Foundation

/// A single field an editor form can change.
///
/// `allCases` doubles as the presentation order: conflicting fields are listed
/// to the user in declaration order, so keep the cases aligned with the form
/// layout.
/// Conformers must be `nonisolated`: the protocol inherits `CaseIterable` and
/// `Hashable`, which cannot be satisfied by a main-actor-isolated conformance.
protocol EditableField: CaseIterable, Hashable {
    /// Human-facing label used when telling the user which fields conflict.
    var displayName: String { get }
}

/// A value copy of every field one editor form can change.
///
/// Taken three times per save: once when the editor loads (the baseline), once
/// from the form's state (what the user is submitting), and once from the model
/// itself at save time (what is stored right now).
/// Conformers must be `nonisolated`, for the same reason as `EditableField`.
protocol EditSnapshot: Equatable {
    associatedtype Field: EditableField

    /// Whether this snapshot and `other` hold different values for `field`.
    func differs(from other: Self, in field: Field) -> Bool

    /// Returns a copy with one field taken from `other`.
    ///
    /// This lets the shared merge rebuild a draft from live values while
    /// overlaying only fields still owned by the user.
    func replacing(_ field: Field, withValueFrom other: Self) -> Self
}

/// Three-way comparison deciding what an editor save should write.
///
/// The editors and the MCP server share `mainContext`, so an MCP write — and a
/// CloudKit merge — lands on the same `@Model` instance the editor is showing.
/// The live values are therefore always readable at save time, and the
/// load-time baseline is the only record of where the user started. Comparing
/// all three separates "the user set this value" from "this is merely what the
/// form loaded", which is what the editors previously could not tell apart
/// (T-1798 for tasks, T-1817 for projects and milestones).
struct EditMerge<Snapshot: EditSnapshot>: Equatable {
    typealias Field = Snapshot.Field

    /// Snapshots are retained because conflict choices authorize exact values,
    /// not every conflict that happens to exist when the button is handled.
    let original: Snapshot
    let edited: Snapshot
    let live: Snapshot

    /// Fields the user changed. Only these are written.
    let changedFields: Set<Field>

    /// Fields the user and an external writer both changed, to different values.
    /// Surfaced to the user rather than resolved automatically — neither side's
    /// value is safe to discard on the user's behalf.
    let conflictingFields: Set<Field>

    var hasChanges: Bool { !changedFields.isEmpty }

    var hasConflicts: Bool { !conflictingFields.isEmpty }

    init(original: Snapshot, edited: Snapshot, live: Snapshot) {
        self.original = original
        self.edited = edited
        self.live = live

        var changed: Set<Field> = []
        var conflicting: Set<Field> = []

        for field in Field.allCases where edited.differs(from: original, in: field) {
            changed.insert(field)

            // Both sides moved away from the baseline. Landing on the same value
            // is agreement, not a conflict.
            if live.differs(from: original, in: field), edited.differs(from: live, in: field) {
                conflicting.insert(field)
            }
        }

        changedFields = changed
        conflictingFields = conflicting
    }

    func changed(_ field: Field) -> Bool {
        changedFields.contains(field)
    }

    /// A draft rebased onto `live` for "Use Updated Values".
    ///
    /// Starting from all live values refreshes fields the user never touched.
    /// Only genuine user edits without conflicts are overlaid; conflicting edits
    /// are deliberately replaced by the live values the user chose to use.
    var rebasedEdited: Snapshot {
        changedFields
            .subtracting(conflictingFields)
            .reduce(live) { snapshot, field in
                snapshot.replacing(field, withValueFrom: edited)
            }
    }

    /// Whether the current conflicts are exactly the ones shown by an alert.
    ///
    /// Matching field names is insufficient: an external writer may change the
    /// same field again while the alert is open. Consent covers the original,
    /// edited, and live values for each shown conflict and nothing else.
    func hasSameConflictSnapshot(as shown: Self) -> Bool {
        guard conflictingFields == shown.conflictingFields else { return false }

        return conflictingFields.allSatisfy { field in
            !original.differs(from: shown.original, in: field)
                && !edited.differs(from: shown.edited, in: field)
                && !live.differs(from: shown.live, in: field)
        }
    }

    /// Conflicting field labels in declaration order, for the conflict alert.
    var conflictingFieldNames: [String] {
        Field.allCases
            .filter(conflictingFields.contains)
            .map(\.displayName)
    }
}
