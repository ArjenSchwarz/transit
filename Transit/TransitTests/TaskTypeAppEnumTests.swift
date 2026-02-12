import Testing
@testable import Transit

@Suite
struct TaskTypeAppEnumTests {
    @Test func caseDisplayRepresentationsCoverAllCases() {
        let map = TaskType.caseDisplayRepresentations
        #expect(map.count == TaskType.allCases.count)

        for value in TaskType.allCases {
            #expect(map[value] != nil)
        }
    }

    @Test func typeDisplayRepresentationIsDefined() {
        _ = TaskType.typeDisplayRepresentation
        #expect(Bool(true))
    }
}
