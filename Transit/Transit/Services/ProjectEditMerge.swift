import Foundation

/// A field of a project that `ProjectEditView` can edit.
///
/// Declaration order is the order fields are listed to the user when they
/// conflict, so keep it aligned with the form layout.
nonisolated enum ProjectEditField: EditableField {
    case name
    case description
    case gitRepo
    case color

    var displayName: String {
        switch self {
        case .name: "Name"
        case .description: "Description"
        case .gitRepo: "Git Repo"
        case .color: "Color"
        }
    }
}

// MARK: - Snapshot

/// A value copy of every field `ProjectEditView` can edit.
///
/// The colour is held as the hex string that is actually stored rather than as a
/// `Color`: comparing `Color` values would compare colour spaces and floating
/// point components instead of the value the project persists.
nonisolated struct ProjectEditSnapshot: EditSnapshot {
    var name: String
    var description: String
    var gitRepo: String
    var colorHex: String

    /// Reads the project's stored values.
    init(project: Project) {
        self.init(
            name: project.name,
            description: project.projectDescription,
            gitRepo: project.gitRepo ?? "",
            colorHex: project.colorHex
        )
    }

    /// Strings are normalised the way the form normalises its input, so loading
    /// a project and saving it again without typing reports no change even when
    /// the stored value carries whitespace the form would have trimmed.
    init(name: String, description: String, gitRepo: String, colorHex: String) {
        self.name = name.trimmedForFormInput()
        self.description = description.trimmedForFormInput()
        self.gitRepo = gitRepo.trimmedForFormInput()
        self.colorHex = Self.normalizedHex(colorHex)
    }

    /// Hex values reach the snapshot both from storage and from
    /// `Color.hexString`, which disagree on the leading `#` and on case. Neither
    /// difference is a change the user made.
    static func normalizedHex(_ hex: String) -> String {
        hex.trimmedForFormInput()
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
    }

    func differs(from other: ProjectEditSnapshot, in field: ProjectEditField) -> Bool {
        switch field {
        case .name: name != other.name
        case .description: description != other.description
        case .gitRepo: gitRepo != other.gitRepo
        case .color: colorHex != other.colorHex
        }
    }
}

// MARK: - Merge

/// Three-way comparison deciding what a project-editor save should write.
///
/// Shares `EditMerge` with the task and milestone editors so all three resolve
/// concurrent writes identically (T-1817).
typealias ProjectEditMerge = EditMerge<ProjectEditSnapshot>

// MARK: - Applier

/// Writes the fields a `ProjectEditMerge` marks as changed, through
/// `ProjectService` so the name invariants still run.
///
/// `updateProject` writes all four fields, so untouched ones are resubmitted
/// with the project's *live* values rather than the form's loaded copy. That is
/// what lets a concurrent MCP or CloudKit write survive a save (T-1817).
struct ProjectEditApplier {
    let projectService: ProjectService

    func apply(_ merge: ProjectEditMerge, edited: ProjectEditSnapshot, to project: Project) throws {
        guard merge.hasChanges else { return }

        try projectService.updateProject(
            project,
            name: merge.changed(.name) ? edited.name : project.name,
            description: merge.changed(.description) ? edited.description : project.projectDescription,
            gitRepo: merge.changed(.gitRepo) ? (edited.gitRepo.isEmpty ? nil : edited.gitRepo) : project.gitRepo,
            colorHex: merge.changed(.color) ? edited.colorHex : project.colorHex
        )
    }
}

// MARK: - Form

/// The project editor's draft state, plus the baseline its save diffs against.
///
/// Held as one value so `load(from:)` can be idempotent. `ProjectEditView`
/// pushes the milestone editor, and popping back fires `onAppear` again — an
/// unconditional reload there wiped whatever the user had typed (T-1880).
///
/// The colour is kept as a hex string rather than a `Color` so the whole draft
/// stays free of SwiftUI and testable; `ProjectEditView` bridges it to
/// `ColorPicker`.
struct ProjectEditForm {
    var name: String = ""
    var description: String = ""
    var gitRepo: String = ""
    var colorHex: String

    /// The project this form was loaded from. Identity, not a bool, so opening
    /// the editor on a different project still reloads.
    private(set) var loadedProjectID: UUID?

    /// The project's values when the editor loaded. Diffing the form against
    /// this baseline is what tells "the user set this" apart from "this is
    /// merely what was loaded", so a save writes only the fields the user
    /// touched (T-1817).
    private(set) var original: ProjectEditSnapshot?

    init(colorHex: String) {
        self.colorHex = ProjectEditSnapshot.normalizedHex(colorHex)
    }

    var canSave: Bool {
        !name.trimmedForFormInput().isEmpty && !description.trimmedForFormInput().isEmpty
    }

    var edited: ProjectEditSnapshot {
        ProjectEditSnapshot(name: name, description: description, gitRepo: gitRepo, colorHex: colorHex)
    }

    /// Copies the project into the form and records the baseline — once per
    /// project. A second call is a no-op, so in-flight edits survive a return
    /// trip through a pushed screen.
    mutating func load(from project: Project) {
        guard loadedProjectID != project.id else { return }

        name = project.name
        description = project.projectDescription
        gitRepo = project.gitRepo ?? ""
        colorHex = ProjectEditSnapshot.normalizedHex(project.colorHex)
        loadedProjectID = project.id
        original = ProjectEditSnapshot(project: project)
    }

    /// The three-way comparison for a save, or `nil` before the form has loaded.
    func merge(against project: Project) -> ProjectEditMerge? {
        guard let original else { return nil }
        return ProjectEditMerge(original: original, edited: edited, live: ProjectEditSnapshot(project: project))
    }

    /// Drops the user's edits to the conflicting fields in favour of the values
    /// now on the project, and re-baselines so untouched fields stay untouched
    /// and the user's other edits stay pending.
    mutating func adoptLiveValues(for merge: ProjectEditMerge, from project: Project) {
        for field in merge.conflictingFields {
            switch field {
            case .name: name = project.name
            case .description: description = project.projectDescription
            case .gitRepo: gitRepo = project.gitRepo ?? ""
            case .color: colorHex = ProjectEditSnapshot.normalizedHex(project.colorHex)
            }
        }
        original = ProjectEditSnapshot(project: project)
    }
}
