import SwiftData
import SwiftUI

/// Observes scenePhase from within a View context (required by SwiftUI) and
/// triggers post-sync maintenance on app launch and return to foreground.
struct ScenePhaseModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var projects: [Project]
    @Query private var milestones: [Milestone]

    let displayIDAllocator: DisplayIDAllocator
    let projectService: ProjectService
    let milestoneService: MilestoneService
    let modelContext: ModelContext

    private var projectNameFingerprint: String {
        projects.map { "\($0.id.uuidString)|\($0.name)" }
            .sorted()
            .joined(separator: "\u{1F}")
    }

    private var milestoneNameFingerprint: String {
        milestones.map {
            "\($0.id.uuidString)|\($0.project?.id.uuidString ?? "orphan")|\($0.name)"
        }
        .sorted()
        .joined(separator: "\u{1F}")
    }

    func body(content: Content) -> some View {
        content
            .task {
                _ = try? projectService.reconcileDuplicateNames()
                await displayIDAllocator.promoteProvisionalTasks(in: modelContext)
                await milestoneService.promoteProvisionalMilestones()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        _ = try? projectService.reconcileDuplicateNames()
                        await displayIDAllocator.promoteProvisionalTasks(in: modelContext)
                        await milestoneService.promoteProvisionalMilestones()
                    }
                }
            }
            .onChange(of: projectNameFingerprint) {
                // CloudKit imports may finish after lifecycle hooks. Query observation
                // supplies a post-sync pass; deferred runs retry on later triggers.
                _ = try? projectService.reconcileDuplicateNames()
            }
            .onChange(of: milestoneNameFingerprint) {
                // CloudKit imports may complete after launch/foreground hooks. Query
                // observation provides the post-sync pass; reconciliation is idempotent.
                try? milestoneService.reconcileDuplicateNames()
            }
    }
}
