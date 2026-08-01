import Foundation

/// A field of a milestone that `MilestoneEditView` can edit.
///
/// Status is deliberately absent: it is changed from the milestone list, not
/// from the editor form.
nonisolated enum MilestoneEditField: EditableField {
    case name
    case description

    var displayName: String {
        switch self {
        case .name: "Name"
        case .description: "Description"
        }
    }
}

// MARK: - Snapshot

/// A value copy of every field `MilestoneEditView` can edit.
nonisolated struct MilestoneEditSnapshot: EditSnapshot {
    var name: String
    var description: String

    /// Reads the milestone's stored values.
    init(milestone: Milestone) {
        self.init(name: milestone.name, description: milestone.milestoneDescription ?? "")
    }

    /// Strings are normalised the way the form normalises its input, so loading
    /// a milestone and saving it again without typing reports no change even
    /// when the stored value carries whitespace the form would have trimmed.
    init(name: String, description: String) {
        self.name = name.trimmedForFormInput()
        self.description = description.trimmedForFormInput()
    }

    func differs(from other: MilestoneEditSnapshot, in field: MilestoneEditField) -> Bool {
        switch field {
        case .name: name != other.name
        case .description: description != other.description
        }
    }

    /// Returns a copy with `field` taken from `other`.
    func replacing(
        _ field: MilestoneEditField,
        withValueFrom other: MilestoneEditSnapshot
    ) -> MilestoneEditSnapshot {
        var copy = self
        switch field {
        case .name: copy.name = other.name
        case .description: copy.description = other.description
        }
        return copy
    }
}

// MARK: - Merge

/// Three-way comparison deciding what a milestone-editor save should write.
///
/// Shares `EditMerge` with the task and project editors so all three resolve
/// concurrent writes identically (T-1817).
typealias MilestoneEditMerge = EditMerge<MilestoneEditSnapshot>

// MARK: - Applier

/// Writes the fields a `MilestoneEditMerge` marks as changed, through
/// `MilestoneService` so the name invariants still run.
///
/// Unchanged fields are passed as `nil`, which `updateMilestone` reads as
/// "leave this alone" — that is what keeps a concurrent writer's value.
struct MilestoneEditApplier {
    let milestoneService: MilestoneService

    func apply(_ merge: MilestoneEditMerge, edited: MilestoneEditSnapshot, to milestone: Milestone) throws {
        guard merge.hasChanges else { return }

        let descriptionChanged = merge.changed(.description)
        try milestoneService.updateMilestone(
            milestone,
            name: merge.changed(.name) ? edited.name : nil,
            // Disambiguates "user emptied the field" from "no change requested"
            // so an existing description can still be removed.
            description: descriptionChanged && !edited.description.isEmpty ? edited.description : nil,
            clearDescription: descriptionChanged && edited.description.isEmpty
        )
    }
}

// MARK: - Form

/// The milestone editor's draft state, plus the baseline its save diffs against.
///
/// Held as one value so `load(from:)` can be idempotent: the editor's `onAppear`
/// fires again whenever a pushed screen is popped, and reloading then would
/// discard whatever the user has typed since (the project-editor half of this is
/// T-1880).
struct MilestoneEditForm {
    var name: String = ""
    var description: String = ""

    /// The milestone this form was loaded from. Identity, not a bool, so opening
    /// the editor on a different milestone still reloads.
    private(set) var loadedMilestoneID: UUID?

    /// The milestone's values when the editor loaded. Diffing the form against
    /// this baseline is what tells "the user set this" apart from "this is
    /// merely what was loaded".
    private(set) var original: MilestoneEditSnapshot?

    var canSave: Bool { !name.trimmedForFormInput().isEmpty }

    var edited: MilestoneEditSnapshot {
        MilestoneEditSnapshot(name: name, description: description)
    }

    /// Copies the milestone into the form and records the baseline — once per
    /// milestone. A second call is a no-op, so in-flight edits survive.
    mutating func load(from milestone: Milestone) {
        guard loadedMilestoneID != milestone.id else { return }

        name = milestone.name
        description = milestone.milestoneDescription ?? ""
        loadedMilestoneID = milestone.id
        original = MilestoneEditSnapshot(milestone: milestone)
    }

    /// The three-way comparison for a save, or `nil` before the form has loaded.
    func merge(against milestone: Milestone) -> MilestoneEditMerge? {
        guard let original else { return nil }
        return MilestoneEditMerge(
            original: original,
            edited: edited,
            live: MilestoneEditSnapshot(milestone: milestone)
        )
    }

    /// Rebuilds the whole draft on the live snapshot shown by the resolved
    /// merge. Starting from live refreshes untouched external changes; only
    /// genuine non-conflicting user edits remain overlaid.
    mutating func adoptLiveValues(for merge: MilestoneEditMerge, from _: Milestone) {
        let rebased = merge.rebasedEdited
        name = rebased.name
        description = rebased.description
        original = merge.live
    }
}
