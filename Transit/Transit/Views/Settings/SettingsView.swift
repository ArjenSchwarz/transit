//
//  SettingsView.swift
//  Transit
//
//  Settings view with Projects and General sections.
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(ProjectService.self) private var projectService
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var selectedProject: Project?
    @State private var showAddProject = false
    @State private var iCloudSyncEnabled = true

    var body: some View {
        Form {
            Section {
                if projects.isEmpty {
                    Text("Create your first project to get started.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(projects) { project in
                        Button {
                            selectedProject = project
                        } label: {
                            HStack(spacing: 12) {
                                ProjectColorDot(color: project.color, size: 32)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(project.name)
                                        .foregroundStyle(.primary)

                                    Text("\(activeTaskCount(for: project)) active tasks")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                HStack {
                    Text("Projects")
                    Spacer()
                    Button {
                        showAddProject = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }

            Section("General") {
                LabeledContent("About Transit") {
                    Text("Version 1.0")
                        .foregroundStyle(.secondary)
                }

                Toggle("iCloud Sync", isOn: $iCloudSyncEnabled)
            }
        }
        .navigationTitle("Settings")
        .navigationBarBackButtonHidden(false)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showAddProject) {
            ProjectEditView(project: nil)
        }
        .sheet(item: $selectedProject) { project in
            ProjectEditView(project: project)
        }
    }

    private func activeTaskCount(for project: Project) -> Int {
        do {
            return try projectService.activeTaskCount(for: project)
        } catch {
            return 0
        }
    }
}
