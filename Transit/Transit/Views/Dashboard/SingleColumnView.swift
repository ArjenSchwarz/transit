import SwiftUI

struct SingleColumnView: View {
    let columns: [DashboardColumn: [TransitTask]]
    @Binding var selectedColumn: DashboardColumn
    let onDropTask: (_ taskID: UUID, _ column: DashboardColumn) -> Bool
    let onSelectTask: (_ task: TransitTask) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Picker("Column", selection: $selectedColumn) {
                ForEach(DashboardColumn.allCases) { column in
                    Text(segmentLabel(for: column)).tag(column)
                }
            }
            .pickerStyle(.segmented)
            .glassEffect()
            .padding(.horizontal)
            .padding(.top, 8)
            .accessibilityIdentifier("dashboard.segmentedControl")
            .accessibilityValue(selectedColumn.rawValue)

            ColumnView(
                column: selectedColumn,
                tasks: columns[selectedColumn] ?? [],
                onDropTask: onDropTask,
                onSelectTask: onSelectTask
            )
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private func segmentLabel(for column: DashboardColumn) -> String {
        let count = columns[column]?.count ?? 0
        return "\(column.primaryStatus.shortLabel) \(count)"
    }
}
