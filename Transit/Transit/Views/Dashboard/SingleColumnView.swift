import SwiftUI

struct SingleColumnView: View {
    let columns: [DashboardColumn: [TransitTask]]
    @Binding var selectedColumn: DashboardColumn
    let onTaskTap: (TransitTask) -> Void
    var onDrop: ((DashboardColumn, String) -> Bool)?

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control with short labels and counts [req 13.1, 13.2]
            Picker("Column", selection: $selectedColumn) {
                ForEach(DashboardColumn.allCases) { column in
                    let count = columns[column]?.count ?? 0
                    Text("\(column.primaryStatus.shortLabel) (\(count))")
                        .tag(column)
                }
            }
            .pickerStyle(.segmented)
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
