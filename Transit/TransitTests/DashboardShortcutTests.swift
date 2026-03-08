import Foundation
import Testing
@testable import Transit

@MainActor
@Suite(.serialized)
struct DashboardShortcutTests {

    // MARK: - Helpers

    private func makeProject(name: String = "Test") -> Project {
        Project(name: name, description: nil, gitRepo: nil, colorHex: "#FF0000")
    }

    // MARK: - shouldHandleNewTaskShortcut

    @Test("Returns true when no sheet is presented")
    func shortcutAllowedWhenNoSheet() {
        let result = DashboardLogic.shouldHandleNewTaskShortcut(
            showAddTask: false, selectedTask: nil
        )
        #expect(result == true)
    }

    @Test("Returns false when Add Task sheet is already showing")
    func shortcutBlockedWhenAddTaskShowing() {
        let result = DashboardLogic.shouldHandleNewTaskShortcut(
            showAddTask: true, selectedTask: nil
        )
        #expect(result == false)
    }

    @Test("Returns false when task detail sheet is showing")
    func shortcutBlockedWhenTaskSelected() {
        let project = makeProject()
        let task = TransitTask(name: "Test", type: .feature, project: project, displayID: .provisional)
        let result = DashboardLogic.shouldHandleNewTaskShortcut(
            showAddTask: false, selectedTask: task
        )
        #expect(result == false)
    }

    @Test("Returns false when both sheets would be showing")
    func shortcutBlockedWhenBothActive() {
        let project = makeProject()
        let task = TransitTask(name: "Test", type: .feature, project: project, displayID: .provisional)
        let result = DashboardLogic.shouldHandleNewTaskShortcut(
            showAddTask: true, selectedTask: task
        )
        #expect(result == false)
    }
}
