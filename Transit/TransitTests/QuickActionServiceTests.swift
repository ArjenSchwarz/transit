#if os(iOS)
import Foundation
import Testing
@testable import Transit

@MainActor
@Suite(.serialized)
struct QuickActionServiceTests {

    @Test("pendingNewTask defaults to false")
    func defaultsToFalse() {
        let service = QuickActionService()
        #expect(service.pendingNewTask == false)
    }

    @Test("pendingNewTask can be set to true")
    func setToTrue() {
        let service = QuickActionService()
        service.pendingNewTask = true
        #expect(service.pendingNewTask == true)
    }

    @Test("pendingNewTask can be cleared after consumption")
    func clearAfterConsumption() {
        let service = QuickActionService()
        service.pendingNewTask = true
        // Simulate consumption (as DashboardView does)
        service.pendingNewTask = false
        #expect(service.pendingNewTask == false)
    }
}
#endif
