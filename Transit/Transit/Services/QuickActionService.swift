#if os(iOS)
import Foundation

@Observable
final class QuickActionService {
    static let newTaskActionType = "com.arjen.transit.new-task"

    /// Scene session identifiers with a pending "new task" action.
    /// Orphaned entries (from scenes closed before consumption) are harmless —
    /// they are never matched again once the scene is gone.
    private(set) var pendingSceneSessionIDs: Set<String> = []

    /// Request a new-task action for a specific scene session.
    func requestNewTask(forSceneSession sessionID: String) {
        pendingSceneSessionIDs.insert(sessionID)
    }

    /// Returns true if the given scene has a pending new-task action.
    func hasPendingAction(forSceneSession sessionID: String) -> Bool {
        pendingSceneSessionIDs.contains(sessionID)
    }

    /// Consume the pending action for a scene. Returns true if there was one.
    @discardableResult
    func consumeNewTask(forSceneSession sessionID: String) -> Bool {
        pendingSceneSessionIDs.remove(sessionID) != nil
    }
}
#endif
