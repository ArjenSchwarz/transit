import Foundation
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TypeFilterMenuTests {
    @Test func togglingTypeAddsAndRemovesSelection() {
        var selectedTypes = Set<TaskType>()

        TypeFilterMenu.setSelection(true, for: .bug, in: &selectedTypes)
        #expect(selectedTypes.contains(.bug))

        TypeFilterMenu.setSelection(false, for: .bug, in: &selectedTypes)
        #expect(selectedTypes.contains(.bug) == false)
    }

    @Test func clearEmptiesSelection() {
        var selectedTypes: Set<TaskType> = [.bug, .feature]

        TypeFilterMenu.clear(&selectedTypes)

        #expect(selectedTypes.isEmpty)
    }

    @Test func countReflectsSelectedTypes() {
        let selectedTypes: Set<TaskType> = [.bug, .feature, .research]

        #expect(TypeFilterMenu.selectionCount(for: selectedTypes) == 3)
    }
}
