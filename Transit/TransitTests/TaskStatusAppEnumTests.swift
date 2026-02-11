import Testing
import AppIntents
@testable import Transit

@MainActor
struct TaskStatusAppEnumTests {

    // MARK: - AppEnum Conformance

    @Test func typeDisplayRepresentationIsConfigured() {
        let typeRep = TaskStatus.typeDisplayRepresentation
        #expect(typeRep.name == "Status")
    }

    @Test func allCasesHaveDisplayRepresentations() {
        let representations = TaskStatus.caseDisplayRepresentations

        for status in TaskStatus.allCases {
            #expect(representations[status] != nil, "Missing display representation for \(status)")
        }
    }

    // MARK: - Display Names

    @Test func ideaDisplayName() {
        let rep = TaskStatus.caseDisplayRepresentations[.idea]
        #expect(rep?.title.key == "Idea")
    }

    @Test func planningDisplayName() {
        let rep = TaskStatus.caseDisplayRepresentations[.planning]
        #expect(rep?.title.key == "Planning")
    }

    @Test func specDisplayName() {
        let rep = TaskStatus.caseDisplayRepresentations[.spec]
        #expect(rep?.title.key == "Spec")
    }

    @Test func readyForImplementationDisplayName() {
        let rep = TaskStatus.caseDisplayRepresentations[.readyForImplementation]
        #expect(rep?.title.key == "Ready for Implementation")
    }

    @Test func inProgressDisplayName() {
        let rep = TaskStatus.caseDisplayRepresentations[.inProgress]
        #expect(rep?.title.key == "In Progress")
    }

    @Test func readyForReviewDisplayName() {
        let rep = TaskStatus.caseDisplayRepresentations[.readyForReview]
        #expect(rep?.title.key == "Ready for Review")
    }

    @Test func doneDisplayName() {
        let rep = TaskStatus.caseDisplayRepresentations[.done]
        #expect(rep?.title.key == "Done")
    }

    @Test func abandonedDisplayName() {
        let rep = TaskStatus.caseDisplayRepresentations[.abandoned]
        #expect(rep?.title.key == "Abandoned")
    }

    // MARK: - Static Properties are Nonisolated

    @Test func staticPropertiesAccessibleFromNonisolatedContext() async {
        // This test verifies that static properties can be accessed from
        // a nonisolated async context without MainActor isolation conflicts
        await Task.detached {
            _ = TaskStatus.typeDisplayRepresentation
            _ = TaskStatus.caseDisplayRepresentations
        }.value
    }
}
