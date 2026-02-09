//
//  SingleColumnView.swift
//  Transit
//
//  Segmented control layout for narrow screens (iPhone portrait).
//

import SwiftUI

struct SingleColumnView: View {
    let columns: [DashboardColumn: [TransitTask]]
    @Binding var selectedColumn: DashboardColumn
    let onTaskTap: (TransitTask) -> Void
    let onDrop: (UUID, DashboardColumn) -> Bool

    var body: some View {
        VStack(spacing: 0) {
            // Segmented control with short labels and counts
            Picker("Column", selection: $selectedColumn) {
                ForEach(DashboardColumn.allCases, id: \.self) { column in
                    Text("\(column.shortLabel) (\(columns[column]?.count ?? 0))")
                        .tag(column)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            // Selected column view
            ColumnView(
                column: selectedColumn,
                tasks: columns[selectedColumn] ?? [],
                onTaskTap: onTaskTap,
                onDrop: onDrop
            )
        }
    }
}

private extension DashboardColumn {
    var shortLabel: String {
        switch self {
        case .idea: return "Idea"
        case .planning: return "Plan"
        case .spec: return "Spec"
        case .inProgress: return "Active"
        case .doneAbandoned: return "Done"
        }
    }
}
