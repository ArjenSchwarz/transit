//
//  FilterPopoverView.swift
//  Transit
//
//  Project filter popover with multi-select checkboxes.
//

import SwiftData
import SwiftUI

struct FilterPopoverView: View {
    @Query(sort: \Project.name) private var projects: [Project]
    @Binding var selectedProjectIDs: Set<UUID>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Filter by Project")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    selectedProjectIDs.removeAll()
                }
                .disabled(selectedProjectIDs.isEmpty)
            }
            .padding()

            Divider()

            // Project list
            if projects.isEmpty {
                Text("No projects")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(projects) { project in
                            ProjectFilterRow(
                                project: project,
                                isSelected: selectedProjectIDs.contains(project.id)
                            ) {
                                toggleProject(project.id)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 250, maxWidth: 300)
        .frame(maxHeight: 400)
    }

    private func toggleProject(_ id: UUID) {
        if selectedProjectIDs.contains(id) {
            selectedProjectIDs.remove(id)
        } else {
            selectedProjectIDs.insert(id)
        }
    }
}

private struct ProjectFilterRow: View {
    let project: Project
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? .blue : .secondary)

                ProjectColorDot(color: project.color, size: 16)

                Text(project.name)
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
