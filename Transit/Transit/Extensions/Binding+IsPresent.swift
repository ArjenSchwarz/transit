import SwiftUI

extension Binding where Value == String? {
    /// Returns a `Binding<Bool>` that is `true` when the wrapped value is non-nil,
    /// and sets the value to `nil` when the binding is set to `false`.
    var isPresent: Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { if !$0 { wrappedValue = nil } }
        )
    }
}
