import Foundation
import SwiftData
import Testing
@testable import Transit

// MARK: - Conflict detection

/// Covers the case the merge cannot resolve on its own: the user and an external
/// writer changed the *same* field. The merge reports it so the editor can ask
/// rather than silently picking a winner.
@MainActor @Suite(.serialized)
struct ProjectEditConflictDetectionTests {

    /// Different values on the same field is a conflict.
    @Test func sameFieldChangedByBothSidesIsAConflict() throws {
        let env = try ProjectEditTestEnv.make()
        let project = try env.makeProject()
        var form = env.loadedForm(for: project)

        try env.projectService.updateProject(
            project,
            name: "Renamed elsewhere",
            description: project.projectDescription,
            gitRepo: project.gitRepo,
            colorHex: project.colorHex
        )

        form.name = "Renamed by the user"

        let merge = try #require(form.merge(against: project))
        #expect(merge.conflictingFields == [.name])
        #expect(merge.conflictingFieldNames == ["Name"])
    }

    /// Both sides landing on the same value is agreement, not a conflict.
    @Test func sameFieldChangedToSameValueIsNotAConflict() throws {
        let env = try ProjectEditTestEnv.make()
        let project = try env.makeProject()
        var form = env.loadedForm(for: project)

        try env.projectService.updateProject(
            project,
            name: "Agreed name",
            description: project.projectDescription,
            gitRepo: project.gitRepo,
            colorHex: project.colorHex
        )

        form.name = "Agreed name"

        let merge = try #require(form.merge(against: project))
        #expect(merge.changedFields == [.name])
        #expect(merge.hasConflicts == false)
    }

    /// Conflicts are per field: a clean edit alongside a conflicting one is
    /// still listed as changed, and a purely external change is neither.
    @Test func conflictsAreDetectedPerFieldNotForTheWholeForm() throws {
        let env = try ProjectEditTestEnv.make()
        let project = try env.makeProject()
        var form = env.loadedForm(for: project)

        try env.projectService.updateProject(
            project,
            name: "Renamed elsewhere",
            description: "Rewritten elsewhere",
            gitRepo: project.gitRepo,
            colorHex: project.colorHex
        )

        form.name = "Renamed by the user"
        form.colorHex = "00FF00"

        let merge = try #require(form.merge(against: project))
        #expect(merge.changedFields == [.name, .color])
        #expect(merge.conflictingFields == [.name])
        #expect(merge.changed(.description) == false)
    }

    /// "Use Updated Values" loads the external values for the conflicting
    /// fields, keeps the user's other edits, and re-baselines so a following
    /// save writes only what is still pending.
    @Test func adoptingLiveValuesKeepsUnrelatedEdits() throws {
        let env = try ProjectEditTestEnv.make()
        let project = try env.makeProject()
        var form = env.loadedForm(for: project)

        try env.projectService.updateProject(
            project,
            name: "Renamed elsewhere",
            description: project.projectDescription,
            gitRepo: project.gitRepo,
            colorHex: project.colorHex
        )

        form.name = "Renamed by the user"
        form.colorHex = "00FF00"

        let merge = try #require(form.merge(against: project))
        form.adoptLiveValues(for: merge, from: project)

        #expect(form.name == "Renamed elsewhere")
        #expect(form.colorHex == "00FF00")

        let rebased = try #require(form.merge(against: project))
        #expect(rebased.changedFields == [.color])
        #expect(rebased.hasConflicts == false)
    }

    /// "Use Updated Values" also refreshes untouched fields changed externally.
    /// Only the user's genuine non-conflicting color edit remains pending after
    /// the draft is rebased onto all current project values.
    @Test func adoptingLiveValuesRefreshesUntouchedExternalFields() throws {
        let env = try ProjectEditTestEnv.make()
        let project = try env.makeProject()
        var form = env.loadedForm(for: project)

        try env.projectService.updateProject(
            project,
            name: "Renamed elsewhere",
            description: "Rewritten elsewhere",
            gitRepo: "https://example.com/external.git",
            colorHex: project.colorHex
        )

        form.name = "Renamed by the user"
        form.colorHex = "00FF00"

        let merge = try #require(form.merge(against: project))
        form.adoptLiveValues(for: merge, from: project)

        #expect(form.name == "Renamed elsewhere")
        #expect(form.description == "Rewritten elsewhere")
        #expect(form.gitRepo == "https://example.com/external.git")
        #expect(form.colorHex == "00FF00")

        let rebased = try #require(form.merge(against: project))
        #expect(rebased.changedFields == [.color])
        #expect(rebased.hasConflicts == false)
    }

    /// Alert consent is tied to the exact conflict field values displayed. A
    /// changed shown value plus a newly conflicting field must invalidate the
    /// old choice so the editor presents the current conflicts instead.
    @Test func changedConflictSnapshotInvalidatesAlertConsent() throws {
        let env = try ProjectEditTestEnv.make()
        let project = try env.makeProject()
        var form = env.loadedForm(for: project)

        form.name = "Renamed by the user"
        form.colorHex = "00FF00"

        try env.projectService.updateProject(
            project,
            name: "First external name",
            description: project.projectDescription,
            gitRepo: project.gitRepo,
            colorHex: project.colorHex
        )
        let shown = try #require(form.merge(against: project))
        #expect(shown.conflictingFields == [.name])

        try env.projectService.updateProject(
            project,
            name: "Second external name",
            description: project.projectDescription,
            gitRepo: project.gitRepo,
            colorHex: project.colorHex
        )
        let changedValue = try #require(form.merge(against: project))
        #expect(changedValue.conflictingFields == [.name])
        #expect(changedValue.hasSameConflictSnapshot(as: shown) == false)

        try env.projectService.updateProject(
            project,
            name: project.name,
            description: project.projectDescription,
            gitRepo: project.gitRepo,
            colorHex: "0000FF"
        )
        let current = try #require(form.merge(against: project))

        #expect(current.conflictingFields == [.name, .color])
        #expect(current.hasSameConflictSnapshot(as: shown) == false)
    }

    /// The alert names the fields and both choices, so the user is not asked a
    /// blind question.
    @Test func conflictDescriptionNamesFieldsAndChoices() throws {
        let env = try ProjectEditTestEnv.make()
        let project = try env.makeProject()
        var form = env.loadedForm(for: project)

        try env.projectService.updateProject(
            project,
            name: "Renamed elsewhere",
            description: project.projectDescription,
            gitRepo: project.gitRepo,
            colorHex: project.colorHex
        )

        form.name = "Renamed by the user"

        let merge = try #require(form.merge(against: project))
        let message = merge.conflictDescription(subject: "Project")

        #expect(message.contains("Name"))
        #expect(message.contains("this project"))
        #expect(message.contains("Keep My Changes"))
        #expect(message.contains("Use Updated Values"))
    }
}
