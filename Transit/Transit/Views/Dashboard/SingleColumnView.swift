import SwiftUI

struct SingleColumnView: View {
    let columns: [DashboardColumn: [TransitTask]]
    @Binding var selectedColumn: DashboardColumn
    let onTaskTap: (TransitTask) -> Void
    var onDrop: ((DashboardColumn, String) -> Bool)?

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control with drop targets [req 13.1, 13.2]
            // ZStack overlays invisible drop zones on the native picker so
            // users can drag a task onto a different tab to change its status.
            ZStack {
                Picker("Column", selection: $selectedColumn) {
                    ForEach(DashboardColumn.allCases) { column in
                        let count = columns[column]?.count ?? 0
                        Text("\(column.primaryStatus.shortLabel) (\(count))")
                            .tag(column)
                    }
                }
                .pickerStyle(.segmented)
                .allowsHitTesting(false)

                HStack(spacing: 0) {
                    ForEach(DashboardColumn.allCases) { column in
                        Color.clear
                            .contentShape(.rect)
                            .onTapGesture { selectedColumn = column }
                            .dropDestination(for: String.self) { items, _ in
                                guard let uuidString = items.first else { return false }
                                return onDrop?(column, uuidString) ?? false
                            } isTargeted: { targeted in
                                if targeted {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedColumn = column
                                    }
                                }
                            }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            ColumnView(
                column: selectedColumn,
                tasks: columns[selectedColumn] ?? [],
                onTaskTap: onTaskTap,
                onDrop: { uuidString in
                    onDrop?(selectedColumn, uuidString) ?? false
                }
            )
        }
    }
}
