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
}
