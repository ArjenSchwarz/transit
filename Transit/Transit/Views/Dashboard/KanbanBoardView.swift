import SwiftUI

struct KanbanBoardView: View {
    let columns: [DashboardColumn: [TransitTask]]
    let visibleCount: Int
    let initialScrollTarget: DashboardColumn?
    let onTaskTap: (TransitTask) -> Void
    var onDrop: ((DashboardColumn, String) -> Bool)?

    var body: some View {
        GeometryReader { geometry in
            let columnWidth = geometry.size.width / CGFloat(min(visibleCount, DashboardColumn.allCases.count))

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(DashboardColumn.allCases) { column in
                            ColumnView(
                                column: column,
                                tasks: columns[column] ?? [],
                                onTaskTap: onTaskTap,
                                onDrop: { uuidString in
                                    onDrop?(column, uuidString) ?? false
                                }
                            )
                            .frame(width: columnWidth)
                            .id(column)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .onAppear {
                    if let target = initialScrollTarget {
                        proxy.scrollTo(target, anchor: .leading)
                    }
                }
            }
        }
    }
}
