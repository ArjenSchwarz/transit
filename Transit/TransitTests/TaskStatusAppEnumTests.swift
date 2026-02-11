import Foundation
import Testing
import AppIntents
@testable import Transit

@MainActor
struct TaskStatusAppEnumTests {

    // MARK: - TypeDisplayRepresentation

    @Test func typeDisplayRepresentationIsStatus() {
        let repr = TaskStatus.typeDisplayRepresentation
        #expect(repr.name == "Status")
    }

    // MARK: - CaseDisplayRepresentations

    @Test func allCasesHaveDisplayRepresentations() {
        let representations = TaskStatus.caseDisplayRepresentations
        for status in TaskStatus.allCases {
            #expect(representations[status] != nil, "Missing display representation for \(status)")
        }
    }

    @Test func displayRepresentationTitlesMatchDisplayNames() {
        let expected: [TaskStatus: String] = [
            .idea: "Idea",
            .planning: "Planning",
            .spec: "Spec",
            .readyForImplementation: "Ready for Implementation",
            .inProgress: "In Progress",
            .readyForReview: "Ready for Review",
            .done: "Done",
            .abandoned: "Abandoned"
        ]

        let representations = TaskStatus.caseDisplayRepresentations
        for (status, expectedTitle) in expected {
            let repr = representations[status]
            #expect(repr?.title == "\(expectedTitle)", "Expected \(expectedTitle) for \(status)")
        }
    }
}
