import Foundation
import SwiftUI
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct BindingToggleSetTests {
    @Test func toggleBindingInsertsOnTrue() {
        let id = UUID()
        var value = Set<UUID>()
        let binding = Binding(get: { value }, set: { value = $0 })

        binding.contains(id).wrappedValue = true

        #expect(value.contains(id))
    }

    @Test func toggleBindingRemovesOnFalse() {
        let id = UUID()
        var value = Set([id])
        let binding = Binding(get: { value }, set: { value = $0 })

        binding.contains(id).wrappedValue = false

        #expect(value.contains(id) == false)
    }

    @Test func toggleBindingReflectsCurrentState() {
        let id = UUID()
        var value = Set([id])
        let binding = Binding(get: { value }, set: { value = $0 })

        #expect(binding.contains(id).wrappedValue)
    }

    @Test func containsReturnsFalseWhenElementNotInSet() {
        var set: Set<String> = ["apple", "banana"]
        let binding = Binding(get: { set }, set: { set = $0 })
        #expect(binding.contains("orange").wrappedValue == false)
    }

    @Test func settingToTrueWhenAlreadyPresentIsIdempotent() {
        var set: Set<String> = ["apple"]
        let binding = Binding(get: { set }, set: { set = $0 })
        binding.contains("apple").wrappedValue = true
        #expect(set.contains("apple"))
        #expect(set.count == 1)
    }

    @Test func settingToFalseWhenNotPresentIsIdempotent() {
        var set: Set<String> = ["apple"]
        let binding = Binding(get: { set }, set: { set = $0 })
        binding.contains("banana").wrappedValue = false
        #expect(!set.contains("banana"))
        #expect(set.count == 1)
    }

    @Test func worksWithTaskTypeSet() {
        var set: Set<TaskType> = [.bug]
        let binding = Binding(get: { set }, set: { set = $0 })

        #expect(binding.contains(.bug).wrappedValue == true)
        #expect(binding.contains(.feature).wrappedValue == false)

        binding.contains(.feature).wrappedValue = true
        #expect(set.contains(.feature))
        #expect(set.count == 2)
    }
}
