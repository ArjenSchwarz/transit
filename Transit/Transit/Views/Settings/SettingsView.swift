import SwiftData
import SwiftUI

struct SettingsView: View {
    @Query(sort: [SortDescriptor(\Project.name)])
    private var projects: [Project]

    @Query private var allTasks: [TransitTask]

    @AppStorage("syncEnabled") private var syncEnabled = true

    var body: some View {
        List {
            projectsSection
            generalSection
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .navigationTitle("Settings")
    }

    private var activeTaskCounts: [UUID: Int] {
        var counts = [UUID: Int](minimumCapacity: projects.count)
        for task in allTasks {
            guard let projectID = task.project?.id, !task.status.isTerminal else {
                continue
            }
            counts[projectID, default: 0] += 1
        }
        return counts
    }

    @ViewBuilder
    private var projectsSection: some View {
        Section {
            if projects.isEmpty {
                EmptyStateView(
                    message: "No projects yet. Tap + to create your first project.",
                    symbol: "folder.badge.plus"
                )
            } else {
                ForEach(projects, id: \.id) { project in
                    NavigationLink {
                        ProjectEditView(project: project)
                    } label: {
                        ProjectRow(
                            project: project,
                            activeCount: activeTaskCounts[project.id] ?? 0
                        )
                    }
                }
            }
        } header: {
            HStack {
                Text("Projects")
                Spacer()
                NavigationLink {
                    ProjectEditView(project: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Project")
            }
        }
    }

    @ViewBuilder
    private var generalSection: some View {
        Section("General") {
            LabeledContent("About Transit") {
                Text(appVersionLabel)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: $syncEnabled) {
                Text("iCloud Sync")
            }
        }
    }

    private var appVersionLabel: String {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let shortVersion, let build {
            return "v\(shortVersion) (\(build))"
        }
        if let shortVersion {
            return "v\(shortVersion)"
        }
        if let build {
            return "Build \(build)"
        }
        return "Unknown"
    }
}

private struct ProjectRow: View {
    let project: Project
    let activeCount: Int

    var body: some View {
        HStack(spacing: 12) {
            ProjectColorDot(
                color: project.color,
                size: 28,
                cornerRadius: 7,
                label: project.name
            )

            Text(project.name)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("\(activeCount)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(activeCount) active tasks")
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
