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

    @Test func availableMilestonesHandlesPersistedStatusTransitionWithDeterministicTerminalPlacement() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let firstProject = Project(name: "First", description: "", gitRepo: nil, colorHex: "#FF0000")
        let secondProject = Project(name: "Second", description: "", gitRepo: nil, colorHex: "#00FF00")
        context.insert(firstProject)
        context.insert(secondProject)

        let alphaOpen = Milestone(name: "Alpha", project: firstProject, displayID: .provisional)
        let betaTransition = Milestone(name: "Beta", project: firstProject, displayID: .provisional)
        let gammaTerminal = Milestone(name: "Gamma", project: firstProject, displayID: .provisional)
        gammaTerminal.status = .abandoned
        let zuluOpen = Milestone(name: "Zulu", project: firstProject, displayID: .provisional)
        let inaccessibleTerminal = Milestone(name: "Other", project: secondProject, displayID: .provisional)
        inaccessibleTerminal.status = .done
        [zuluOpen, gammaTerminal, alphaOpen, inaccessibleTerminal, betaTransition].forEach(context.insert)
        try context.save()

        let selectedMilestones: Set<UUID> = [
            betaTransition.id,
            gammaTerminal.id,
            inaccessibleTerminal.id
        ]
        let initiallyAvailable = MilestoneFilterMenu.availableMilestones(
            milestones: try context.fetch(FetchDescriptor<Milestone>()),
            projects: [firstProject, secondProject],
            selectedProjectIDs: [firstProject.id],
            selectedMilestones: selectedMilestones
        )
        let initialAvailableIDs: [UUID] = initiallyAvailable.map(\.id)
        let initialExpectedIDs: [UUID] = [
            alphaOpen.id, betaTransition.id, zuluOpen.id, gammaTerminal.id
        ]
        #expect(initialAvailableIDs == initialExpectedIDs)

        betaTransition.status = .done
        try context.save()

        let transitionedAvailable = MilestoneFilterMenu.availableMilestones(
            milestones: try context.fetch(FetchDescriptor<Milestone>()),
            projects: [firstProject, secondProject],
            selectedProjectIDs: [firstProject.id],
            selectedMilestones: selectedMilestones
        )
        let transitionedAvailableIDs: [UUID] = transitionedAvailable.map(\.id)
        let transitionedExpectedIDs: [UUID] = [
            alphaOpen.id, zuluOpen.id, betaTransition.id, gammaTerminal.id
        ]
        #expect(transitionedAvailableIDs == transitionedExpectedIDs)
    }

    @Test func multiProjectOrderingMatchesDisplayedMilestoneTitles() {
        let compactProject = Project(name: "A", description: "", gitRepo: nil, colorHex: "#FF0000")
        let spacedProject = Project(name: "A ", description: "", gitRepo: nil, colorHex: "#00FF00")
        let compactMilestone = Milestone(name: "Aaa", project: compactProject, displayID: .provisional)
        let spacedMilestone = Milestone(name: "Aaa", project: spacedProject, displayID: .provisional)
        let spacedTerminal = Milestone(name: "Release", project: spacedProject, displayID: .provisional)
        spacedTerminal.status = .done

        let available = MilestoneFilterMenu.availableMilestones(
            milestones: [spacedTerminal, compactMilestone, spacedMilestone],
            projects: [compactProject, spacedProject],
            selectedProjectIDs: [],
            selectedMilestones: [spacedTerminal.id]
        )
        let titles = available.map {
            MilestoneFilterMenu.milestoneTitle(for: $0, selectedProjectIDs: [])
        }

        #expect(titles == ["A  - Aaa", "A - Aaa", "A  - Release"])
    }

    @Test func deletedSelectedMilestoneLeavesMenuAvailableForClear() throws {
        let testContainer = try TestModelContainer()
        let context = testContainer.context
        let project = Project(name: "Project", description: "", gitRepo: nil, colorHex: "#FF0000")
        let milestone = Milestone(name: "Deleted", project: project, displayID: .provisional)
        context.insert(project)
        context.insert(milestone)
        try context.save()

        context.delete(milestone)
        try context.save()
        let available = MilestoneFilterMenu.availableMilestones(
            milestones: try context.fetch(FetchDescriptor<Milestone>()),
            projects: [project],
            selectedProjectIDs: [project.id],
            selectedMilestones: [milestone.id]
        )

        #expect(available.isEmpty)
        #expect(MilestoneFilterMenu.shouldShowMenu(
            availableMilestones: available,
            selectedMilestones: [milestone.id]
        ))
    }

    @Test func accessibilityLabelsIncludeTerminalStatusWithoutSelectionDuplication() {
        let project = Project(name: "Project", description: "", gitRepo: nil, colorHex: "#FF0000")
        let openMilestone = Milestone(name: "Open", project: project, displayID: .provisional)
        let doneMilestone = Milestone(name: "Closed", project: project, displayID: .provisional)
        doneMilestone.status = .done
        let abandonedMilestone = Milestone(name: "Retired", project: project, displayID: .provisional)
        abandonedMilestone.status = .abandoned

        #expect(MilestoneFilterMenu.milestoneAccessibilityLabel(
            for: openMilestone,
            selectedProjectIDs: [project.id]
        ) == "Open")
        #expect(MilestoneFilterMenu.milestoneAccessibilityLabel(
            for: doneMilestone,
            selectedProjectIDs: [project.id]
        ) == "Closed, Done")
        #expect(MilestoneFilterMenu.milestoneAccessibilityLabel(
            for: abandonedMilestone,
            selectedProjectIDs: [project.id]
        ) == "Retired, Abandoned")
    }
}
