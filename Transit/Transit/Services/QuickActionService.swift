#if os(iOS)
import Foundation

@Observable
final class QuickActionService {
    static let newTaskActionType = "com.arjen.transit.new-task"

    /// Scene session identifiers with a pending "new task" action.
    /// Using an ordered array so SwiftUI can observe changes per element.
    var pendingSceneSessionIDs: [String] = []

    /// Request a new-task action for a specific scene session.
    func requestNewTask(forSceneSession sessionID: String) {
        guard !pendingSceneSessionIDs.contains(sessionID) else { return }
        pendingSceneSessionIDs.append(sessionID)
    }

    /// Returns true if the given scene has a pending new-task action.
    func hasPendingAction(forSceneSession sessionID: String) -> Bool {
        pendingSceneSessionIDs.contains(sessionID)
    }

    /// Consume the pending action for a scene. Returns true if there was one.
    @discardableResult
    func consumeNewTask(forSceneSession sessionID: String) -> Bool {
        guard let index = pendingSceneSessionIDs.firstIndex(of: sessionID) else {
            return false
        }
        pendingSceneSessionIDs.remove(at: index)
        return true
    }
}
#endif
