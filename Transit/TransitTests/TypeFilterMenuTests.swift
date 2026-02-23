import Foundation
import SwiftUI
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct TypeFilterMenuTests {
    @Test func togglingTypeAddsAndRemovesSelection() {
        var selectedTypes = Set<TaskType>()
        let binding = Binding(get: { selectedTypes }, set: { selectedTypes = $0 })

        binding.contains(TaskType.bug).wrappedValue = true
        #expect(selectedTypes.contains(.bug))

        binding.contains(TaskType.bug).wrappedValue = false
        #expect(selectedTypes.contains(.bug) == false)
    }

    @Test func accessibilityLabelReflectsCount() {
        #expect(TypeFilterMenu.accessibilityLabel(for: 0) == "Task type filter, 0 selected")
        #expect(TypeFilterMenu.accessibilityLabel(for: 3) == "Task type filter, 3 selected")
    }
}
