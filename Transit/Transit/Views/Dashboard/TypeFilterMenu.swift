import SwiftUI

struct TypeFilterMenu: View {
    @Binding var selectedTypes: Set<TaskType>
    @Environment(\.horizontalSizeClass) private var sizeClass

    #if os(macOS)
    @State private var showPopover = false
    #endif

    var body: some View {
        menuContent
            .accessibilityIdentifier("dashboard.filter.types")
            .accessibilityLabel(Self.accessibilityLabel(for: Self.selectionCount(for: selectedTypes)))
    }

    @ViewBuilder
    private var menuContent: some View {
        #if os(macOS)
        Button { showPopover.toggle() } label: { filterLabel }
            .popover(isPresented: $showPopover) {
                List {
                    toggleContent
                    clearSection
                }
                .frame(minWidth: 220, minHeight: 200)
            }
        #else
        Menu {
            Section {
                toggleContent
            }
            .menuActionDismissBehavior(.disabled)

            clearSection
        } label: {
            filterLabel
        }
        #endif
    }

    @ViewBuilder
    private var toggleContent: some View {
        ForEach(TaskType.allCases, id: \.self) { type in
            Toggle(isOn: $selectedTypes.contains(type)) {
                Label(type.rawValue.capitalized, systemImage: "circle.fill")
                    .foregroundStyle(type.tintColor)
            }
        }
    }

    @ViewBuilder
    private var clearSection: some View {
        if !selectedTypes.isEmpty {
            Section {
                Button("Clear", role: .destructive) {
                    Self.clear(&selectedTypes)
                }
            }
        }
    }

    @ViewBuilder
    private var filterLabel: some View {
        let count = Self.selectionCount(for: selectedTypes)
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

    static func setSelection(_ isSelected: Bool, for type: TaskType, in selectedTypes: inout Set<TaskType>) {
        if isSelected {
            selectedTypes.insert(type)
        } else {
            selectedTypes.remove(type)
        }
    }

    static func clear(_ selectedTypes: inout Set<TaskType>) {
        selectedTypes.removeAll()
    }

    static func selectionCount(for selectedTypes: Set<TaskType>) -> Int {
        selectedTypes.count
    }

    static func accessibilityLabel(for count: Int) -> String {
        "Task type filter, \(count) selected"
    }
}
