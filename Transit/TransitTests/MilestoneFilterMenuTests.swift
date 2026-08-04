import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Transit

@MainActor @Suite(.serialized)
struct MilestoneFilterMenuTests {
    @Test func togglingMilestoneAddsAndRemovesSelection() {
        let milestoneID = UUID()
        var selectedMilestones = Set<UUID>()
        let binding = Binding(get: { selectedMilestones }, set: { selectedMilestones = $0 })

        binding.contains(milestoneID).wrappedValue = true
        #expect(selectedMilestones.contains(milestoneID))

        binding.contains(milestoneID).wrappedValue = false
        #expect(selectedMilestones.contains(milestoneID) == false)
    }

    @Test func menuHiddenWhenNoAvailableAndNoneSelected() {
        #expect(MilestoneFilterMenu.shouldShowMenu(availableMilestones: [], selectedMilestones: []) == false)
    }

    @Test func visibleMilestoneIDsPreservesOpenOrderAndDeduplicatesSelectedMilestones() {
        let firstOpenID = UUID()
        let secondOpenID = UUID()
        let doneID = UUID()
        let abandonedID = UUID()

        let visibleIDs = MilestoneFilterMenu.visibleMilestoneIDs(
            openMilestoneIDs: [firstOpenID, secondOpenID, firstOpenID],
            selectedAccessibleMilestoneIDs: [doneID, secondOpenID, abandonedID, doneID]
        )

        #expect(visibleIDs == [firstOpenID, secondOpenID, doneID, abandonedID])
    }

    @Test func availableMilestonesKeepsSelectedTerminalMilestonesWithinSelectedProjects() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: allocator)

        let firstProject = Project(name: "First", description: "", gitRepo: nil, colorHex: "#FF0000")
        let secondProject = Project(name: "Second", description: "", gitRepo: nil, colorHex: "#00FF00")
        context.insert(firstProject)
        context.insert(secondProject)

        let openMilestone = Milestone(name: "Open", project: firstProject, displayID: .provisional)
        let doneMilestone = Milestone(name: "Done", project: firstProject, displayID: .provisional)
        doneMilestone.status = .done
        let abandonedMilestone = Milestone(name: "Abandoned", project: firstProject, displayID: .provisional)
        abandonedMilestone.status = .abandoned
        let inaccessibleMilestone = Milestone(
            name: "Other project", project: secondProject, displayID: .provisional
        )
        inaccessibleMilestone.status = .done
        [openMilestone, doneMilestone, abandonedMilestone, inaccessibleMilestone].forEach(context.insert)
        try context.save()

        let available = MilestoneFilterMenu.availableMilestones(
            projects: [firstProject, secondProject],
            selectedProjectIDs: [firstProject.id],
            selectedMilestones: [
                openMilestone.id,
                doneMilestone.id,
                abandonedMilestone.id,
                inaccessibleMilestone.id
            ],
            milestoneService: milestoneService
        )

        let selectedTerminalIDs = milestoneService.milestonesForProject(firstProject)
            .filter { $0.status.isTerminal && [doneMilestone.id, abandonedMilestone.id].contains($0.id) }
            .map(\.id)
        #expect(available.map(\.id) == [openMilestone.id] + selectedTerminalIDs)
    }

    @Test func menuRemainsAvailableForAnInaccessibleSelectedMilestone() {
        #expect(MilestoneFilterMenu.shouldShowMenu(
            availableMilestones: [],
            selectedMilestones: [UUID()]
        ))
    }
}
