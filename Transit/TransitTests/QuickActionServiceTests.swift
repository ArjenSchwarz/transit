#if os(iOS)
import Foundation
import Testing
@testable import Transit

@MainActor
@Suite(.serialized)
struct QuickActionServiceTests {

    @Test("no pending action by default")
    func defaultsToNoPending() {
        let service = QuickActionService()
        #expect(!service.hasPendingAction(forSceneSession: "scene-A"))
    }

    @Test("pending action is scoped to the requesting scene")
    func pendingScopedToScene() {
        let service = QuickActionService()
        service.requestNewTask(forSceneSession: "scene-A")
        #expect(service.hasPendingAction(forSceneSession: "scene-A"))
        #expect(!service.hasPendingAction(forSceneSession: "scene-B"))
    }

    @Test("consume clears only the matching scene")
    func consumeClearsMatchingScene() {
        let service = QuickActionService()
        service.requestNewTask(forSceneSession: "scene-A")
        let consumed = service.consumeNewTask(forSceneSession: "scene-A")
        #expect(consumed)
        #expect(!service.hasPendingAction(forSceneSession: "scene-A"))
    }

    @Test("consume returns false for non-matching scene")
    func consumeReturnsFalseForWrongScene() {
        let service = QuickActionService()
        service.requestNewTask(forSceneSession: "scene-A")
        let consumed = service.consumeNewTask(forSceneSession: "scene-B")
        #expect(!consumed)
        // Original scene's pending action is still there
        #expect(service.hasPendingAction(forSceneSession: "scene-A"))
    }

    @Test("multiple scenes can have independent pending actions")
    func multipleScenesPending() {
        let service = QuickActionService()
        service.requestNewTask(forSceneSession: "scene-A")
        service.requestNewTask(forSceneSession: "scene-B")
        #expect(service.hasPendingAction(forSceneSession: "scene-A"))
        #expect(service.hasPendingAction(forSceneSession: "scene-B"))

        _ = service.consumeNewTask(forSceneSession: "scene-A")
        #expect(!service.hasPendingAction(forSceneSession: "scene-A"))
        #expect(service.hasPendingAction(forSceneSession: "scene-B"))
    }

    @Test("pendingSceneSessionIDs tracks all pending scenes for observation")
    func pendingSceneSessionIDsObservable() {
        let service = QuickActionService()
        #expect(service.pendingSceneSessionIDs.isEmpty)
        service.requestNewTask(forSceneSession: "scene-A")
        #expect(service.pendingSceneSessionIDs == ["scene-A"])
        service.requestNewTask(forSceneSession: "scene-B")
        #expect(service.pendingSceneSessionIDs == ["scene-A", "scene-B"])
        _ = service.consumeNewTask(forSceneSession: "scene-A")
        #expect(service.pendingSceneSessionIDs == ["scene-B"])
    }
}
#endif
