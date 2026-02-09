//
//  KanbanBoardView.swift
//  Transit
//
//  Multi-column horizontal scrolling kanban board.
//

import SwiftUI

struct KanbanBoardView: View {
    let columns: [DashboardColumn: [TransitTask]]
    let onTaskTap: (TransitTask) -> Void
    let onDrop: (UUID, DashboardColumn) -> Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 16) {
                ForEach(DashboardColumn.allCases, id: \.self) { column in
                    ColumnView(
                        column: column,
                        tasks: columns[column] ?? [],
                        onTaskTap: onTaskTap,
                        onDrop: onDrop
                    )
                    .frame(width: 300)
                }
            }
            .padding()
        }
    }
}
