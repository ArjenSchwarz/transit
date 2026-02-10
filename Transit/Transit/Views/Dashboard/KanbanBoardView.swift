import SwiftUI

struct KanbanBoardView: View {
    let columns: [DashboardColumn: [TransitTask]]
    let visibleCount: Int
    let initialScrollTarget: DashboardColumn?
    let onDropTask: (_ taskID: UUID, _ column: DashboardColumn) -> Bool
    let onSelectTask: (_ task: TransitTask) -> Void

    private var columnWidth: CGFloat {
        let boundedVisibleCount = max(1, min(5, visibleCount))
        return 320 / CGFloat(boundedVisibleCount) * 1.25
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(DashboardColumn.allCases) { column in
                        ColumnView(
                            column: column,
                            tasks: columns[column] ?? [],
                            onDropTask: onDropTask,
                            onSelectTask: onSelectTask
                        )
                        .frame(width: max(240, columnWidth))
                        .id(column)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .onAppear {
                guard let initialScrollTarget else {
                    return
                }
                proxy.scrollTo(initialScrollTarget, anchor: .leading)
            }
        }
    }
}
