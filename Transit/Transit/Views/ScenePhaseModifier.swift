import SwiftData
import SwiftUI

/// Observes scenePhase from within a View context (required by SwiftUI) and
/// triggers display ID promotion on app launch and return to foreground.
struct ScenePhaseModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    let displayIDAllocator: DisplayIDAllocator
    let milestoneService: MilestoneService
    let modelContext: ModelContext

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
    }
}
