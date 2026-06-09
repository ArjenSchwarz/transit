import SwiftUI

struct PriorityFilterMenu: View {
    @Binding var selectedPriorities: Set<TaskPriority>
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showPopover = false

    var body: some View {
        Button { showPopover.toggle() } label: { filterLabel }
            .accessibilityIdentifier("dashboard.filter.priorities")
            .accessibilityLabel(Self.accessibilityLabel(for: selectedPriorities.count))
            #if os(macOS)
            .popover(isPresented: $showPopover) {
                List {
                    Section {
                        toggleContent
                    }
                    clearSection
                }
                .frame(minWidth: 220, minHeight: 200)
            }
            #else
            .sheet(isPresented: $showPopover) {
                NavigationStack {
                    List {
                        toggleContent
                        clearSection
                    }
                    .navigationTitle("Priorities")
                    .toolbarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showPopover = false }
                        }
                    }
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            #endif
    }

    @ViewBuilder
    private var toggleContent: some View {
        // Iterate displayOrder (high → medium → low), not allCases (low-first),
        // so the most actionable value reads first.
        ForEach(TaskPriority.displayOrder, id: \.self) { priority in
            Button {
                $selectedPriorities.contains(priority).wrappedValue.toggle()
            } label: {
                HStack {
                    Circle()
                        .fill(priority.tintColor)
                        .frame(width: 12, height: 12)
                    Text(priority.rawValue.capitalized)
                        .foregroundStyle(.primary)
                    Spacer()
                    if selectedPriorities.contains(priority) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("filter.priority.\(priority.rawValue)")
        }
    }

    @ViewBuilder
    private var clearSection: some View {
        if !selectedPriorities.isEmpty {
            Section {
                Button("Clear", role: .destructive) {
                    selectedPriorities.removeAll()
                }
            }
        }
    }

    @ViewBuilder
    private var filterLabel: some View {
        let count = selectedPriorities.count
        if sizeClass == .compact {
            Image(systemName: count > 0 ? "flag.fill" : "flag")
                .badge(count)
        } else {
            Label(
                count > 0 ? "Priorities (\(count))" : "Priorities",
                systemImage: count > 0 ? "flag.fill" : "flag"
            )
        }
    }

    static func accessibilityLabel(for count: Int) -> String {
        "Priority filter, \(count) selected"
    }
}
