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
    let state: TaskConsolidationNativeState
    let onRefresh: () -> Void
    @State private var navigationProblem: String?
    #if os(iOS)
    @State private var expandedOperations: Set<UUID> = []
    @State private var expandedAccounting: Set<UUID> = []
    @State private var expandedChanges: Set<ChangeExpansionKey> = []
    #endif
    var body: some View {
        #if os(iOS)
        historyRows
        #else
        VStack(alignment: .leading, spacing: 8) { historyRows }
            .disclosureGroupStyle(HistoryDisclosureStyle())
        #endif
    }
    @ViewBuilder private var historyRows: some View {
        historyHeading
        if let value = state.observation {
            if value.history.isEmpty { Text("No saved consolidation history").foregroundStyle(.secondary) }
            ForEach(value.history, id: \.operationId) { entry in history(entry, observation: value) }
        } else { Text(state.problem ?? "Loading saved history…").foregroundStyle(.secondary) }
        if let navigationProblem { Text(navigationProblem).foregroundStyle(.secondary) }
    }
    private var historyHeading: some View {
        Text("Consolidation history").font(.caption).foregroundStyle(.secondary)
            .accessibilityIdentifier("consolidation.history.\(taskID.uuidString)")
    }
    @ViewBuilder private func history(_ entry: ConsolidationHistoryProjection,
                                      observation: TaskConsolidationNativeObservation) -> some View {
        #if os(iOS)
        iOSHistory(entry, observation: observation)
        #else
        macOSHistory(entry, observation: observation)
        #endif
    }
    #if os(macOS)
    @ViewBuilder private func macOSHistory(_ entry: ConsolidationHistoryProjection,
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
    #endif
    @ViewBuilder private func destination(_ id: UUID, label: String, operationID: UUID,
                                          observation: TaskConsolidationNativeObservation) -> some View {
        let matches = observation.tasks.filter { $0.id == id }
        if matches.count == 1, let task = matches.first {
            Button("\(label): \(task.name) · \(id.uuidString)") {
                do {
                    guard let destination = try TaskLinkNavigationResolver.resolve(id, in: context) else {
                        navigationProblem = "The saved task is missing or ambiguous."
                        onRefresh()
                        return
                    }
                    navigationProblem = nil
                    onSelect(destination)
                } catch { navigationProblem = "The saved task cannot be resolved." }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
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
    private struct HistoryDisclosureStyle: DisclosureGroupStyle {
        func makeBody(configuration: Configuration) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Button { configuration.isExpanded.toggle() } label: {
                    HStack {
                        configuration.label
                        Spacer()
                        Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
                if configuration.isExpanded { configuration.content.padding(.leading, 12) }
            }
        }
    }
}

#if os(iOS)
private extension TaskConsolidationHistorySection {
    struct ChangeExpansionKey: Hashable {
        let operationID: UUID
        let taskID: UUID
    }
    @ViewBuilder func iOSHistory(_ entry: ConsolidationHistoryProjection,
                                 observation: TaskConsolidationNativeObservation) -> some View {
        let operationID = entry.operationId
        rowDisclosure(entry.apply.reason, identifier: "consolidation.reason.\(operationID.uuidString)",
                      expanded: expandedOperations.contains(operationID)) {
            toggle(operationID, in: &expandedOperations)
        }
        if expandedOperations.contains(operationID) {
            Text("Operation: \(operationID.uuidString)").font(.caption).textSelection(.enabled)
            Text(entry.reversal == nil ? "Applied" : "Reversed")
                .accessibilityIdentifier("consolidation.state.\(operationID.uuidString)")
            Text(entry.undoAvailable ? "Whole reversal available" :
                "Whole reversal unavailable: \(entry.undoUnavailableReason ?? "unavailable")")
                .font(.caption).foregroundStyle(.secondary)
            rowDisclosure("Preservation accounting", identifier: "consolidation.accounting.\(operationID.uuidString)",
                          expanded: expandedAccounting.contains(operationID)) {
                toggle(operationID, in: &expandedAccounting)
            }
            if expandedAccounting.contains(operationID) {
                Text(entry.apply.preservationJSON).font(.caption).textSelection(.enabled)
                    .accessibilityIdentifier("consolidation.preservation.\(operationID.uuidString)")
            }
            ForEach([entry.apply.survivorTaskId] + entry.apply.candidateTaskIds, id: \.self) { id in
                destination(id, label: "Original task", operationID: operationID, observation: observation)
            }
            iOSChanges(entry, operationID: operationID)
            ForEach(entry.apply.mappings ?? [], id: \.sourceTaskId) { mapping in
                Text("Recorded path: \(mapping.path.map(\.uuidString).joined(separator: " → "))").font(.caption)
                if let target = mapping.canonicalTaskId {
                    destination(target, label: "Recorded canonical task", operationID: operationID,
                                observation: observation)
                }
            }
            if let reversal = entry.reversalId { Text("Reversal: \(reversal.uuidString)").font(.caption) }
        }
    }
    @ViewBuilder func iOSChanges(_ entry: ConsolidationHistoryProjection, operationID: UUID) -> some View {
        ForEach(entry.apply.changes, id: \.taskId) { change in
            let key = ChangeExpansionKey(operationID: operationID, taskID: change.taskId)
            rowDisclosure("Saved changes: \(change.taskId.uuidString)",
                          identifier: "consolidation.changes.\(operationID.uuidString).\(change.taskId.uuidString)",
                          expanded: expandedChanges.contains(key)) {
                toggle(key, in: &expandedChanges)
            }
            if expandedChanges.contains(key) {
                ForEach(change.fields.keys.sorted(), id: \.self) { field in
                    if let delta = change.fields[field] {
                        Text("\(field): \(display(delta.before, field: field)) → "
                            + "\(display(delta.after, field: field))")
                            .font(.caption).textSelection(.enabled)
                    }
                }
            }
        }
    }
    func rowDisclosure(_ title: String, identifier: String, expanded: Bool,
                       toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
    }
    func toggle<Key: Hashable>(_ key: Key, in values: inout Set<Key>) {
        if !values.insert(key).inserted { values.remove(key) }
    }
}
#endif
