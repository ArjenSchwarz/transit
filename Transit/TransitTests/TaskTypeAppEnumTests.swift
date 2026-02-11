import Testing
import AppIntents
@testable import Transit

@MainActor
struct TaskTypeAppEnumTests {

    // MARK: - AppEnum Conformance

    @Test func typeDisplayRepresentationIsConfigured() {
        let typeRep = TaskType.typeDisplayRepresentation
        #expect(typeRep.name == "Type")
    }

    @Test func allCasesHaveDisplayRepresentations() {
        let representations = TaskType.caseDisplayRepresentations
        
        for type in TaskType.allCases {
            #expect(representations[type] != nil, "Missing display representation for \(type)")
        }
    }

    // MARK: - Display Names

    @Test func bugDisplayName() {
        let rep = TaskType.caseDisplayRepresentations[.bug]
        #expect(rep?.title.key == "Bug")
    }

    @Test func featureDisplayName() {
        let rep = TaskType.caseDisplayRepresentations[.feature]
        #expect(rep?.title.key == "Feature")
    }

    @Test func choreDisplayName() {
        let rep = TaskType.caseDisplayRepresentations[.chore]
        #expect(rep?.title.key == "Chore")
    }

    @Test func researchDisplayName() {
        let rep = TaskType.caseDisplayRepresentations[.research]
        #expect(rep?.title.key == "Research")
    }

    @Test func documentationDisplayName() {
        let rep = TaskType.caseDisplayRepresentations[.documentation]
        #expect(rep?.title.key == "Documentation")
    }

    // MARK: - Static Properties are Nonisolated

    @Test func staticPropertiesAccessibleFromNonisolatedContext() async {
        // This test verifies that static properties can be accessed from
        // a nonisolated async context without MainActor isolation conflicts
        await Task.detached {
            let _ = TaskType.typeDisplayRepresentation
            let _ = TaskType.caseDisplayRepresentations
        }.value
    }
}
