import Foundation
import Observation

@MainActor @Observable final class TaskConsolidationNativeState {
    private(set) var sourceID: UUID?
    private(set) var observation: TaskConsolidationNativeObservation?
    private(set) var problem: String?
    private var generation: UInt64 = 0

    func refresh(source: UUID, wait: @escaping @MainActor () async throws -> Void = {},
                 provider: @escaping @MainActor (UUID) async -> TaskConsolidationNativeObservation) async {
        guard !Task.isCancelled else { return }
        sourceID = source
        generation &+= 1
        let admitted = generation
        observation = nil
        problem = nil
        do { try await wait() } catch { return }
        guard !Task.isCancelled, generation == admitted, sourceID == source else { return }
        let value = await provider(source)
        guard !Task.isCancelled, generation == admitted, sourceID == source else { return }
        guard value.taskId == source, value.problem == nil else {
            problem = value.problem ?? "Saved consolidation history no longer matches this task."
            return
        }
        observation = value
    }
}
