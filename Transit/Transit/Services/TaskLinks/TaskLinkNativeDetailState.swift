import Foundation
import Observation

/// Value-only native observation; selected identity and generation own publication.
@MainActor @Observable final class TaskLinkNativeDetailState {
    private(set) var sourceID: UUID?
    private(set) var detail: TaskLinkSavedDetail?
    private(set) var problem: String?
    private var generation: UInt64 = 0

    func refresh(source: UUID, debounce: Duration = .zero,
                 provider: @escaping @MainActor (UUID) async throws -> TaskLinkSavedDetail) async {
        await refresh(source: source, wait: {
            if debounce > .zero { try await Task.sleep(for: debounce) }
        }, provider: provider)
    }

    /// Waiting belongs after invalidation, so an earlier capture cannot publish
    /// during a notification burst. The provider still captures the complete saved graph.
    func refresh(source: UUID, wait: @escaping @MainActor () async throws -> Void,
                 provider: @escaping @MainActor (UUID) async throws -> TaskLinkSavedDetail) async {
        guard !Task.isCancelled else { return }
        sourceID = source
        generation &+= 1
        let accepted = generation
        detail = nil
        problem = nil
        do {
            try await wait()
            guard !Task.isCancelled, generation == accepted, sourceID == source else { return }
            let observation = try await provider(source)
            guard !Task.isCancelled, generation == accepted, sourceID == source else { return }
            detail = observation
        } catch {
            guard !Task.isCancelled, generation == accepted, sourceID == source else { return }
            problem = "Saved relationships are unavailable until this task can be uniquely resolved."
        }
    }
}
