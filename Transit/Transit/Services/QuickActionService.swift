#if os(iOS)
import Foundation

@Observable
final class QuickActionService {
    static let newTaskActionType = "com.arjen.transit.new-task"

    var pendingNewTask = false
}
#endif
