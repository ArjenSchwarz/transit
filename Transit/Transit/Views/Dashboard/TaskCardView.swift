//
//  TaskCardView.swift
//  Transit
//
//  Task card with glass effect, project color border, and key task info.
//

import SwiftUI

struct TaskCardView: View {
    let task: TransitTask
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Header: Project name and Display ID
                HStack {
                    if let project = task.project {
                        Text(project.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(task.displayID.formatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Task name with strikethrough for abandoned
                Text(task.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .strikethrough(task.status == .abandoned)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Type badge
                TypeBadge(type: task.type)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
            .glassEffect()
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        task.project?.color.opacity(0.6) ?? Color.gray.opacity(0.3),
                        lineWidth: 1.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .opacity(task.status == .abandoned ? 0.5 : 1.0)
        .draggable(task.id.uuidString)
    }
}
