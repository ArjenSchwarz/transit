import Foundation
import SwiftData
import Testing
@testable import Transit

// MARK: - Shared fixture

/// A `ProjectService` wired to one context, the way the app wires the UI and the
/// MCP server: both write to the same `Project` instance.
@MainActor
struct ProjectEditTestEnv {
    let context: ModelContext
    let projectService: ProjectService
    let applier: ProjectEditApplier

    static func make() throws -> ProjectEditTestEnv {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let projectService = ProjectService(modelContext: context)
        return ProjectEditTestEnv(
            context: context,
            projectService: projectService,
            applier: ProjectEditApplier(projectService: projectService)
        )
    }

    @discardableResult
    func makeProject(
        name: String = "Transit",
        description: String = "Original description",
        gitRepo: String? = "https://example.com/transit.git",
        colorHex: String = "FF0000"
    ) throws -> Project {
        try projectService.createProject(
            name: name,
            description: description,
            gitRepo: gitRepo,
            colorHex: colorHex
        )
    }

    /// The form as it exists the moment the editor has appeared.
    func loadedForm(for project: Project) -> ProjectEditForm {
        var form = ProjectEditForm(colorHex: "0000FF")
        form.load(from: project)
        return form
    }

    /// Runs the save the editor would run for `form`.
    func save(_ form: ProjectEditForm, to project: Project) throws {
        guard let merge = form.merge(against: project) else { return }
        try applier.apply(merge, edited: form.edited, to: project)
    }
}

// MARK: - Concurrent update regression

/// Regression tests for T-1817.
///
/// `ProjectEditView` snapshotted every editable field into `@State` on appear
/// and wrote all of them back on save, so any change an external writer (MCP
/// over the shared `mainContext`, or a CloudKit merge) made to the live project
/// while the editor was open was silently reverted by the next save.
@MainActor @Suite(.serialized)
struct ProjectEditConcurrentUpdateTests {

    /// The scenario from T-1817: open the editor, let another writer rename the
    /// project, change only the colour in the form, save. The rename survives.
    @Test func externalUpdateSurvivesUnrelatedFormEdit() throws {
        let env = try ProjectEditTestEnv.make()
        let project = try env.makeProject()
        var form = env.loadedForm(for: project)

        // Another window / MCP / CloudKit writes to the same live project.
        try env.projectService.updateProject(
            project,
            name: "Renamed elsewhere",
            description: "Rewritten elsewhere",
            gitRepo: "https://example.com/renamed.git",
            colorHex: "FF0000"
        )

        // The user touches only the colour picker.
        form.colorHex = "00FF00"

        let merge = try #require(form.merge(against: project))
        #expect(merge.changedFields == [.color])
        #expect(merge.hasConflicts == false)

        try env.save(form, to: project)

        #expect(project.colorHex == "00FF00")
        #expect(project.name == "Renamed elsewhere")
        #expect(project.projectDescription == "Rewritten elsewhere")
        #expect(project.gitRepo == "https://example.com/renamed.git")
    }

    /// A save with no form edits at all must not write anything, so an external
    /// change survives the user merely opening and closing the editor.
    @Test func untouchedFormWritesNothing() throws {
        let env = try ProjectEditTestEnv.make()
        let project = try env.makeProject()
        let form = env.loadedForm(for: project)

        try env.projectService.updateProject(
            project,
            name: "Renamed elsewhere",
            description: "Original description",
            gitRepo: nil,
            colorHex: "123456"
        )

        let merge = try #require(form.merge(against: project))
        #expect(merge.hasChanges == false)

        try env.save(form, to: project)

        #expect(project.name == "Renamed elsewhere")
        #expect(project.gitRepo == nil)
        #expect(project.colorHex == "123456")
    }

    /// An external repository-URL change survives a name-only form edit.
    @Test func externalGitRepoChangeSurvivesNameEdit() throws {
        let env = try ProjectEditTestEnv.make()
        let project = try env.makeProject(gitRepo: nil)
        var form = env.loadedForm(for: project)

        try env.projectService.updateProject(
            project,
            name: project.name,
            description: project.projectDescription,
            gitRepo: "https://example.com/added-elsewhere.git",
            colorHex: project.colorHex
        )

        form.name = "Renamed by the user"

        let merge = try #require(form.merge(against: project))
        #expect(merge.changedFields == [.name])

        try env.save(form, to: project)

        #expect(project.name == "Renamed by the user")
        #expect(project.gitRepo == "https://example.com/added-elsewhere.git")
    }

    /// Clearing the repository field still removes the stored URL — the merge
    /// must not read "emptied" as "untouched".
    @Test func clearingGitRepoStillRemovesIt() throws {
        let env = try ProjectEditTestEnv.make()
        let project = try env.makeProject()
        var form = env.loadedForm(for: project)

        form.gitRepo = ""

        let merge = try #require(form.merge(against: project))
        #expect(merge.changedFields == [.gitRepo])

        try env.save(form, to: project)

        #expect(project.gitRepo == nil)
    }

    /// Ordinary editing still applies every field the user touched.
    @Test func ordinaryEditAppliesAllTouchedFields() throws {
        let env = try ProjectEditTestEnv.make()
        let project = try env.makeProject()
        var form = env.loadedForm(for: project)

        form.name = "New name"
        form.description = "New description"
        form.gitRepo = "https://example.com/new.git"
        form.colorHex = "ABCDEF"

        try env.save(form, to: project)

        #expect(project.name == "New name")
        #expect(project.projectDescription == "New description")
        #expect(project.gitRepo == "https://example.com/new.git")
        #expect(project.colorHex == "ABCDEF")
    }

    /// Stored colour hexes are written in several shapes ("#ff0000" vs
    /// "FF0000"). Loading one and saving must not look like a colour edit.
    @Test func colourFormattingDifferencesAreNotEdits() throws {
        let env = try ProjectEditTestEnv.make()
        let project = try env.makeProject(colorHex: "#ff0000")
        let form = env.loadedForm(for: project)

        let merge = try #require(form.merge(against: project))
        #expect(merge.changed(.color) == false)
    }

    /// Loading and immediately saving must not look like an edit just because
    /// the stored value carries whitespace the form would have trimmed.
    @Test func untrimmedStoredValuesDoNotLookLikeEdits() throws {
        let env = try ProjectEditTestEnv.make()
        let project = try env.makeProject()
        project.projectDescription = "  Original description\n"

        let form = env.loadedForm(for: project)
        let merge = try #require(form.merge(against: project))

        #expect(merge.hasChanges == false)
    }
}

// MARK: - Draft lifecycle (T-1880)

/// Regression tests for T-1880.
///
/// `ProjectEditView.loadProject()` ran unconditionally from `onAppear`. The view
/// contains `NavigationLink`s to the milestone editor, so popping back fired
/// `onAppear` again and overwrote the user's unsaved draft with the persisted
/// values.
@MainActor @Suite(.serialized)
struct ProjectEditDraftLifecycleTests {

    /// The repro from T-1880: edit without saving, push the milestone editor,
    /// come back. The draft must still be there.
    @Test func draftSurvivesReturnFromMilestoneEditor() throws {
        let env = try ProjectEditTestEnv.make()
        let project = try env.makeProject()
        var form = env.loadedForm(for: project)

        form.name = "Unsaved name"
        form.description = "Unsaved description"
        form.gitRepo = "https://example.com/unsaved.git"
        form.colorHex = "00FF00"

        // Popping MilestoneEditView fires ProjectEditView.onAppear a second time.
        form.load(from: project)

        #expect(form.name == "Unsaved name")
        #expect(form.description == "Unsaved description")
        #expect(form.gitRepo == "https://example.com/unsaved.git")
        #expect(form.colorHex == "00FF00")
    }

    /// The reload guard must not freeze the baseline either: after the second
    /// `onAppear` a save still writes exactly the fields the user changed.
    @Test func baselineSurvivesReturnFromMilestoneEditor() throws {
        let env = try ProjectEditTestEnv.make()
        let project = try env.makeProject()
        var form = env.loadedForm(for: project)

        form.name = "Unsaved name"
        form.load(from: project)

        let merge = try #require(form.merge(against: project))
        #expect(merge.changedFields == [.name])

        try env.save(form, to: project)
        #expect(project.name == "Unsaved name")
    }

    /// Guarding on project identity, not on a plain "already loaded" flag, so a
    /// reused form still picks up a different project.
    @Test func loadingADifferentProjectReplacesTheDraft() throws {
        let env = try ProjectEditTestEnv.make()
        let first = try env.makeProject(name: "First")
        let second = try env.makeProject(name: "Second", description: "Second description")

        var form = env.loadedForm(for: first)
        form.name = "Unsaved name"

        form.load(from: second)

        #expect(form.name == "Second")
        #expect(form.description == "Second description")
    }
}
