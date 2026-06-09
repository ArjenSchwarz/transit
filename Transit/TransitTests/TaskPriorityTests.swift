import SwiftUI
import Testing
@testable import Transit

@MainActor
struct TaskPriorityTests {

    // MARK: - Raw values

    @Test func rawValuesMatchSpec() {
        #expect(TaskPriority.low.rawValue == "low")
        #expect(TaskPriority.medium.rawValue == "medium")
        #expect(TaskPriority.high.rawValue == "high")
    }

    @Test func rawValueInitializerRoundTrips() {
        #expect(TaskPriority(rawValue: "low") == .low)
        #expect(TaskPriority(rawValue: "medium") == .medium)
        #expect(TaskPriority(rawValue: "high") == .high)
    }

    // MARK: - allCases

    @Test func allCasesContainsThreeLevels() {
        #expect(TaskPriority.allCases == [.low, .medium, .high])
    }

    // MARK: - displayOrder

    @Test func displayOrderIsHighToLow() {
        // Pickers and the board filter iterate displayOrder (most-actionable
        // first), not allCases (source order). This ordering is user-visible.
        #expect(TaskPriority.displayOrder == [.high, .medium, .low])
    }

    // MARK: - tintColor

    @Test func tintColorMatchesSpec() {
        #expect(TaskPriority.high.tintColor == .red)
        #expect(TaskPriority.medium.tintColor == .orange)
        #expect(TaskPriority.low.tintColor == .blue)
    }

    // MARK: - glyphSymbol

    @Test func glyphSymbolIsNilOnlyForMedium() {
        #expect(TaskPriority.medium.glyphSymbol == nil)
        #expect(TaskPriority.high.glyphSymbol == "arrow.up.circle.fill")
        #expect(TaskPriority.low.glyphSymbol == "arrow.down.circle.fill")
    }

    // MARK: - accessibilityLabel

    @Test func accessibilityLabelsNamePriorityLevel() {
        #expect(TaskPriority.high.accessibilityLabel == "High priority")
        #expect(TaskPriority.medium.accessibilityLabel == "Medium priority")
        #expect(TaskPriority.low.accessibilityLabel == "Low priority")
    }
}
