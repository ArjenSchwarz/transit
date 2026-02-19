import SwiftUI
import Testing
@testable import Transit

@MainActor
struct BindingIsPresentTests {

    @Test func isPresentReturnsFalseWhenNil() {
        var value: String?
        let binding = Binding(get: { value }, set: { value = $0 })
        #expect(binding.isPresent.wrappedValue == false)
    }

    @Test func isPresentReturnsTrueWhenNonNil() {
        var value: String? = "error"
        let binding = Binding(get: { value }, set: { value = $0 })
        #expect(binding.isPresent.wrappedValue == true)
    }

    @Test func settingIsPresentToFalseClearsValue() {
        var value: String? = "error"
        let binding = Binding(get: { value }, set: { value = $0 })
        binding.isPresent.wrappedValue = false
        #expect(value == nil)
    }

    @Test func settingIsPresentToTrueDoesNothing() {
        var value: String?
        let binding = Binding(get: { value }, set: { value = $0 })
        binding.isPresent.wrappedValue = true
        #expect(value == nil)
    }
}
