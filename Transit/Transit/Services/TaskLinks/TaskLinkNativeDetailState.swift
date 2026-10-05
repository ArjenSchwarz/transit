import Foundation
import Observation

/// Value-only native observation. UI wiring follows cancellation/generation RED.
@MainActor @Observable final class TaskLinkNativeDetailState {
    private(set) var sourceID: UUID?
    private(set) var detail: TaskLinkSavedDetail?
    private(set) var problem: String?

    func refresh(source: UUID,
                 provider: @escaping @MainActor (UUID) async throws -> TaskLinkSavedDetail) async {
        sourceID = source
        detail = nil
        problem = nil
        do { detail = try await provider(source) }
        catch { problem = "Saved relationships are unavailable until this task can be uniquely resolved." }
    }
}
