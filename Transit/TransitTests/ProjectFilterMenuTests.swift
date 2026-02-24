import Foundation
import SwiftUI
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct ProjectFilterMenuTests {
    @Test func togglingProjectAddsAndRemovesSelection() {
        let projectID = UUID()
        var selectedProjectIDs = Set<UUID>()
        let menu = ProjectFilterMenu(
            projects: [],
            selectedProjectIDs: Binding(
                get: { selectedProjectIDs },
                set: { selectedProjectIDs = $0 }
            )
        )

        menu.toggleBinding(for: projectID).wrappedValue = true
        #expect(selectedProjectIDs.contains(projectID))

        menu.toggleBinding(for: projectID).wrappedValue = false
        #expect(selectedProjectIDs.contains(projectID) == false)
    }

    @Test func clearEmptiesSelectedProjects() {
        var selectedProjectIDs = Set([UUID(), UUID()])
        let menu = ProjectFilterMenu(
            projects: [],
            selectedProjectIDs: Binding(
                get: { selectedProjectIDs },
                set: { selectedProjectIDs = $0 }
            )
        )

        menu.clearSelection()

        #expect(selectedProjectIDs.isEmpty)
    }

    @Test func countReflectsSelectedProjects() {
        var selectedProjectIDs = Set([UUID(), UUID(), UUID()])
        let menu = ProjectFilterMenu(
            projects: [],
            selectedProjectIDs: Binding(
                get: { selectedProjectIDs },
                set: { selectedProjectIDs = $0 }
            )
        )

        #expect(menu.selectionCount == 3)
    }
}
