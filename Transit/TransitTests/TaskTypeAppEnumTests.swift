import Foundation
import Testing
import AppIntents
@testable import Transit

@MainActor
struct TaskTypeAppEnumTests {

    // MARK: - TypeDisplayRepresentation

    @Test func typeDisplayRepresentationIsType() {
        let repr = TaskType.typeDisplayRepresentation
        #expect(repr.name == "Type")
    }

    // MARK: - CaseDisplayRepresentations

    @Test func allCasesHaveDisplayRepresentations() {
        let representations = TaskType.caseDisplayRepresentations
        for type in TaskType.allCases {
            #expect(representations[type] != nil, "Missing display representation for \(type)")
        }
    }

    @Test func displayRepresentationTitlesMatchExpected() {
        let expected: [TaskType: String] = [
            .bug: "Bug",
            .feature: "Feature",
            .chore: "Chore",
            .research: "Research",
            .documentation: "Documentation"
        ]

        let representations = TaskType.caseDisplayRepresentations
        for (type, expectedTitle) in expected {
            let repr = representations[type]
            #expect(repr?.title == "\(expectedTitle)", "Expected \(expectedTitle) for \(type)")
        }
    }
}
