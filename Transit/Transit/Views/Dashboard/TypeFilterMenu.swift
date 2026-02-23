import SwiftUI

struct TypeFilterMenu: View {
    @Binding var selectedTypes: Set<TaskType>
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showPopover = false

    var body: some View {
        Button { showPopover.toggle() } label: { filterLabel }
            .accessibilityIdentifier("dashboard.filter.types")
            .accessibilityLabel(Self.accessibilityLabel(for: selectedTypes.count))
            #if os(macOS)
            .popover(isPresented: $showPopover) {
                List {
                    toggleContent
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
                    .navigationTitle("Types")
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
        ForEach(TaskType.allCases, id: \.self) { type in
            Button {
                $selectedTypes.contains(type).wrappedValue.toggle()
            } label: {
                HStack {
                    Circle()
                        .fill(type.tintColor)
                        .frame(width: 12, height: 12)
                    Text(type.rawValue.capitalized)
                        .foregroundStyle(.primary)
                    Spacer()
                    if selectedTypes.contains(type) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("filter.type.\(type.rawValue)")
        }
    }

    @ViewBuilder
    private var clearSection: some View {
        if !selectedTypes.isEmpty {
            Section {
                Button("Clear", role: .destructive) {
                    selectedTypes.removeAll()
                }
            }
        }
    }

    @ViewBuilder
    private var filterLabel: some View {
        let count = selectedTypes.count
        if sizeClass == .compact {
            Image(systemName: count > 0 ? "tag.fill" : "tag")
                .badge(count)
        } else {
            Label(
                count > 0 ? "Types (\(count))" : "Types",
                systemImage: count > 0 ? "tag.fill" : "tag"
            )
        }
    }

    static func accessibilityLabel(for count: Int) -> String {
        "Task type filter, \(count) selected"
    }
}
