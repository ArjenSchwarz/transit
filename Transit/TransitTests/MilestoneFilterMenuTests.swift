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

    @Test func availableMilestonesScopedToSelectedProjects() throws {
        let context = try TestModelContainer.newContext()
        let allocator = DisplayIDAllocator(store: InMemoryCounterStore())
        let milestoneService = MilestoneService(modelContext: context, displayIDAllocator: allocator)

        let firstProject = Project(name: "First", description: "", gitRepo: nil, colorHex: "#FF0000")
        let secondProject = Project(name: "Second", description: "", gitRepo: nil, colorHex: "#00FF00")
        context.insert(firstProject)
        context.insert(secondProject)

        let firstMilestone = Milestone(name: "M1", project: firstProject, displayID: .provisional)
        let secondMilestone = Milestone(name: "M2", project: secondProject, displayID: .provisional)
        context.insert(firstMilestone)
        context.insert(secondMilestone)
        try context.save()

        let available = MilestoneFilterMenu.availableMilestones(
            projects: [firstProject, secondProject],
            selectedProjectIDs: [firstProject.id],
            milestoneService: milestoneService
        )

        #expect(Set(available.map(\.id)) == [firstMilestone.id])
    }
}
