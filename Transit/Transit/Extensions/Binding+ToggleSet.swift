import SwiftUI

extension Binding {
    /// Creates a Bool binding that toggles membership of `element` in a Set.
    func contains<Element: Hashable>(_ element: Element) -> Binding<Bool>
    where Value == Set<Element> {
        Binding<Bool>(
            get: { wrappedValue.contains(element) },
            set: { isOn in
                if isOn {
                    wrappedValue.insert(element)
                } else {
                    wrappedValue.remove(element)
                }
            }
        )
    }
}
