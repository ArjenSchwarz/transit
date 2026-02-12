import Testing
@testable import Transit

@Suite
struct TaskStatusAppEnumTests {
    @Test func caseDisplayRepresentationsCoverAllCases() {
        let map = TaskStatus.caseDisplayRepresentations
        #expect(map.count == TaskStatus.allCases.count)

        for value in TaskStatus.allCases {
            #expect(map[value] != nil)
        }
    }

    @Test func typeDisplayRepresentationIsDefined() {
        _ = TaskStatus.typeDisplayRepresentation
        #expect(Bool(true))
    }
}
