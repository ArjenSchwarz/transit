import SwiftUI

extension Binding where Value == Milestone? {
    /// Creates a UUID-based binding suitable for SwiftUI Pickers,
    /// avoiding the `Hashable` requirement on `@Model` classes.
    func milestoneID(from milestones: [Milestone]) -> Binding<UUID?> {
        Binding<UUID?>(
            get: { wrappedValue?.id },
            set: { newID in
                wrappedValue = milestones.first { $0.id == newID }
            }
        )
    }
}
