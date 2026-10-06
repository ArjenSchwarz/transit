import CoreData
import SwiftData
import SwiftUI
private struct ConsolidationHistoryReaderKey: EnvironmentKey {
    static let defaultValue: TaskConsolidationNativeReader? = nil
}
extension EnvironmentValues {
    var consolidationHistoryReader: TaskConsolidationNativeReader? {
        get { self[ConsolidationHistoryReaderKey.self] }
        set { self[ConsolidationHistoryReaderKey.self] = newValue }
    }
}
/// Saved immutable history is separate from current relationship assessments.
struct TaskConsolidationHistorySection: View {
    let taskID: UUID
    let onSelect: (TransitTask) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.consolidationHistoryReader) private var reader
    @State private var state = TaskConsolidationNativeState()
    @State private var version: UInt64 = 0
    @State private var navigationProblem: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Consolidation history").font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("consolidation.history.\(taskID.uuidString)")
            if let value = state.observation {
                if value.history.isEmpty { Text("No saved consolidation history").foregroundStyle(.secondary) }
                ForEach(value.history, id: \.operationId) { entry in history(entry, observation: value) }
            } else { Text(state.problem ?? "Loading saved history…").foregroundStyle(.secondary) }
            if let navigationProblem { Text(navigationProblem).foregroundStyle(.secondary) }
        }
        .task(id: RefreshKey(id: taskID, version: version)) {
            let debounce = state.sourceID == taskID
            await state.refresh(source: taskID, wait: {
                if debounce { try await Task.sleep(for: .milliseconds(100)) }
            }, provider: { id in
                guard let reader else {
                    return TaskConsolidationNativeObservation(taskId: id, history: [], tasks: [],
                        problem: "Saved consolidation history is unavailable.")
                }
                return await reader.read(id)
            })
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in version &+= 1 }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in version &+= 1 }
    }
    @ViewBuilder private func history(_ entry: ConsolidationHistoryProjection,
                                      observation: TaskConsolidationNativeObservation) -> some View {
        DisclosureGroup {
            Text("Operation: \(entry.operationId.uuidString)").font(.caption).textSelection(.enabled)
            Text(entry.reversal == nil ? "Applied" : "Reversed")
                .accessibilityIdentifier("consolidation.state.\(entry.operationId.uuidString)")
            Text(entry.undoAvailable ? "Whole reversal available" :
                "Whole reversal unavailable: \(entry.undoUnavailableReason ?? "unavailable")")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup {
                Text(entry.apply.preservationJSON).font(.caption).textSelection(.enabled)
                    .accessibilityIdentifier("consolidation.preservation.\(entry.operationId.uuidString)")
            } label: {
                Text("Preservation accounting")
                    .accessibilityIdentifier("consolidation.accounting.\(entry.operationId.uuidString)")
            }
            ForEach([entry.apply.survivorTaskId] + entry.apply.candidateTaskIds, id: \.self) { id in
                destination(id, label: "Original task", operationID: entry.operationId, observation: observation)
            }
            ForEach(entry.apply.changes, id: \.taskId) { change in
                DisclosureGroup("Saved changes: \(change.taskId.uuidString)") {
                    ForEach(change.fields.keys.sorted(), id: \.self) { field in
                        if let delta = change.fields[field] {
                            Text("\(field): \(display(delta.before, field: field)) → "
                                + "\(display(delta.after, field: field))")
                                .font(.caption).textSelection(.enabled)
                        }
                    }
                }
            }
            ForEach(entry.apply.mappings ?? [], id: \.sourceTaskId) { mapping in
                Text("Recorded path: \(mapping.path.map(\.uuidString).joined(separator: " → "))").font(.caption)
                if let target = mapping.canonicalTaskId {
                    destination(target, label: "Recorded canonical task", operationID: entry.operationId,
                        observation: observation)
                }
            }
            if let reversal = entry.reversalId { Text("Reversal: \(reversal.uuidString)").font(.caption) }
        } label: {
            Text(entry.apply.reason)
                .accessibilityIdentifier("consolidation.reason.\(entry.operationId.uuidString)")
        }
    }
    @ViewBuilder private func destination(_ id: UUID, label: String, operationID: UUID,
                                          observation: TaskConsolidationNativeObservation) -> some View {
        let matches = observation.tasks.filter { $0.id == id }
        if matches.count == 1, let task = matches.first {
            Button("\(label): \(task.name) · \(id.uuidString)") {
                do {
                    guard let destination = try TaskLinkNavigationResolver.resolve(id, in: context) else {
                        navigationProblem = "The saved task is missing or ambiguous."
                        version &+= 1
                        return
                    }
                    navigationProblem = nil
                    onSelect(destination)
                } catch { navigationProblem = "The saved task cannot be resolved." }
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("consolidation.destination.\(operationID.uuidString)."
                + "\(label == "Original task" ? "original" : "canonical").\(id.uuidString)")
        } else { Text("Unresolved \(label.lowercased()): \(id.uuidString)").foregroundStyle(.secondary) }
    }
    private func display(_ value: String?, field: String) -> String {
        guard let value else { return "null" }
        if ["lastStatusChangeDate", "completionDate"].contains(field),
           let date = try? TaskConsolidationRawFields.date(value) { return date.formatted() }
        return value
    }
    private struct RefreshKey: Hashable { let id: UUID; let version: UInt64 }
}
