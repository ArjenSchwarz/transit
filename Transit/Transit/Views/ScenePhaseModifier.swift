import SwiftData
import SwiftUI

/// Observes scenePhase from within a View context (required by SwiftUI) and
/// triggers display ID promotion on app launch and return to foreground.
struct ScenePhaseModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var milestones: [Milestone]

    let displayIDAllocator: DisplayIDAllocator
    let milestoneService: MilestoneService
    let modelContext: ModelContext

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
                await displayIDAllocator.promoteProvisionalTasks(in: modelContext)
                await milestoneService.promoteProvisionalMilestones()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        await displayIDAllocator.promoteProvisionalTasks(in: modelContext)
                        await milestoneService.promoteProvisionalMilestones()
                    }
                }
            }
            .onChange(of: milestoneNameFingerprint) {
                // CloudKit imports may complete after launch/foreground hooks. Query
                // observation provides the post-sync pass; reconciliation is idempotent.
                try? milestoneService.reconcileDuplicateNames()
            }
    }
}
