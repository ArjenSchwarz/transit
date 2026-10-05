import CoreData
import SwiftData
import SwiftUI

struct TaskLinksSection: View {
    let taskID: UUID
    let onSelect: (TransitTask) -> Void
    @Environment(\.modelContext) private var context
    @State private var state = TaskLinkNativeDetailState()
    @State private var refreshVersion: UInt64 = 0
    @State private var navigationProblem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved relationships")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("task-links.observation.\(taskID.uuidString)")
            if let detail = state.detail {
                content(detail)
            } else {
                Text(state.problem ?? "Loading saved relationships…").foregroundStyle(.secondary)
            }
            if let navigationProblem { Text(navigationProblem).foregroundStyle(.secondary) }
        }
        .task(id: RefreshKey(source: taskID, version: refreshVersion)) {
            let service = TaskLinkService(container: context.container)
            let debounce: Duration = state.sourceID == taskID ? .milliseconds(100) : .zero
            await state.refresh(source: taskID, debounce: debounce) { source in
                try Task.checkCancellation()
                return try service.savedDetail(for: source, budget: TaskLinkGraphBudget(checkpoint: {
                    try Task.checkCancellation()
                }))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in refreshVersion &+= 1 }
        .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
            refreshVersion &+= 1
        }
    }

    @ViewBuilder private func content(_ detail: TaskLinkSavedDetail) -> some View {
        let rows = detail.graph.incidence[taskID, default: []]
        Text("Blockers: \(detail.graph.assessment(for: taskID).rawValue.capitalized)")
        if rows.isEmpty { Text("No recorded relationships").foregroundStyle(.secondary) }
        ForEach(rows, id: \.physicalKey) { row in
            relationship(row, graph: detail.graph)
        }
        if let canonical = detail.duplicateResolution.canonical, canonical != taskID {
            Text("Canonical task: \(canonical.uuidString)").font(.caption)
        }
        if let diagnostic = detail.duplicateResolution.diagnostic {
            Text(diagnostic.replacingOccurrences(of: "_", with: " ").capitalized).foregroundStyle(.secondary)
        }
        ForEach(Array(detail.graph.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
            if diagnostic.taskIds.contains(taskID) {
                Text(diagnostic.code.replacingOccurrences(of: "_", with: " ").capitalized)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("task-links.diagnostic.\(diagnostic.code)")
            }
        }
    }

    @ViewBuilder private func relationship(_ row: TaskLinkOccurrenceValue, graph: TaskLinkGraphView) -> some View {
        let incoming = row.target == taskID
        let target = incoming ? row.source : row.target
        let matches = graph.tasksById[target, default: []]
        let title = TaskLinkNativeLabels.title(kind: row.kind, incoming: incoming)
        if matches.count == 1, let value = matches.first {
            Button {
                do {
                    guard let selected = try TaskLinkNavigationResolver.resolve(target, in: context) else {
                        navigationProblem = "This saved destination is missing or ambiguous."
                        refreshVersion &+= 1
                        return
                    }
                    navigationProblem = nil
                    onSelect(selected)
                } catch { navigationProblem = "This saved destination cannot be resolved." }
            } label: {
                VStack(alignment: .leading) {
                    Text("\(title): \(value.name)")
                    Text("\(incoming ? "Incoming" : "Outgoing") · \(target.uuidString)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("task-links.target.\(target.uuidString)")
        } else {
            Text("\(title): Unresolved \(target.uuidString)").foregroundStyle(.secondary)
        }
    }

    private struct RefreshKey: Hashable { let source: UUID; let version: UInt64 }
}
