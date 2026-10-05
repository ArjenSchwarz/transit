import Foundation
import Observation

/// Value-only native observation; selected identity and generation own publication.
@MainActor @Observable final class TaskLinkNativeDetailState {
    private(set) var sourceID: UUID?
    private(set) var detail: TaskLinkSavedDetail?
    private(set) var problem: String?
    private var generation: UInt64 = 0

    func refresh(source: UUID,
                 provider: @escaping @MainActor (UUID) async throws -> TaskLinkSavedDetail) async {
        sourceID = source
        generation &+= 1
        let accepted = generation
        detail = nil
        problem = nil
        do {
            let observation = try await provider(source)
            guard !Task.isCancelled, generation == accepted, sourceID == source else { return }
            detail = observation
        } catch {
            guard !Task.isCancelled, generation == accepted, sourceID == source else { return }
            problem = "Saved relationships are unavailable until this task can be uniquely resolved."
        }
    }
}
