import Foundation
import SwiftData

enum UITestScenario: String {
    case empty
    case board
    case duplicateDisplayIds

    // swiftlint:disable:next function_body_length
    func seed(into ctx: ModelContext) {
        switch self {
        case .empty:
            return
        case .duplicateDisplayIds:
            seedDuplicateDisplayIds(into: ctx)
            return
        case .board:
            break
        }

        let now = Date()

        let alpha = Project(
            name: "Alpha", description: "Primary project", gitRepo: nil, colorHex: "#0A84FF"
        )
        let beta = Project(
            name: "Beta", description: "Secondary project", gitRepo: nil, colorHex: "#30D158"
        )
        ctx.insert(alpha)
        ctx.insert(beta)

        let shipActive = TransitTask(
            name: "Ship Active", description: nil, type: .feature, project: alpha, displayID: .permanent(1)
        )
        shipActive.creationDate = now.addingTimeInterval(-120)
        shipActive.lastStatusChangeDate = now.addingTimeInterval(-60)
        shipActive.statusRawValue = TaskStatus.inProgress.rawValue
        ctx.insert(shipActive)

        let backlogIdea = TransitTask(
            name: "Backlog Idea", description: nil, type: .research, project: alpha, displayID: .permanent(2)
        )
        backlogIdea.creationDate = now.addingTimeInterval(-560)
        backlogIdea.lastStatusChangeDate = now.addingTimeInterval(-500)
        backlogIdea.statusRawValue = TaskStatus.idea.rawValue
        ctx.insert(backlogIdea)

        let oldAbandoned = TransitTask(
            name: "Old Abandoned", description: nil, type: .chore, project: alpha, displayID: .permanent(3)
        )
        oldAbandoned.creationDate = now.addingTimeInterval(-360)
        oldAbandoned.lastStatusChangeDate = now.addingTimeInterval(-300)
        oldAbandoned.statusRawValue = TaskStatus.abandoned.rawValue
        oldAbandoned.completionDate = now.addingTimeInterval(-300)
        ctx.insert(oldAbandoned)

        let betaReview = TransitTask(
            name: "Beta Review", description: nil, type: .bug, project: beta, displayID: .permanent(4)
        )
        betaReview.creationDate = now.addingTimeInterval(-260)
        betaReview.lastStatusChangeDate = now.addingTimeInterval(-200)
        betaReview.statusRawValue = TaskStatus.readyForReview.rawValue
        ctx.insert(betaReview)

        let alphaV1 = Milestone(
            name: "v1.0", description: "First release", project: alpha, displayID: .permanent(1)
        )
        ctx.insert(alphaV1)
        shipActive.milestone = alphaV1
        backlogIdea.milestone = alphaV1

        let betaV1 = Milestone(name: "Beta v1", description: nil, project: beta, displayID: .permanent(2))
        ctx.insert(betaV1)
        betaReview.milestone = betaV1
    }

    /// Seeds duplicate-displayId data exercised by `DataMaintenanceUITests`.
    /// Includes both a duplicate task pair and a duplicate milestone pair at
    /// the SAME display ID number (T-5 and M-5) — this matches T-1062's
    /// scenario where the result view combines task and milestone groups
    /// and must keep them distinct in SwiftUI's diff.
    private func seedDuplicateDisplayIds(into ctx: ModelContext) {
        let now = Date()

        let project = Project(
            name: "Alpha", description: "Primary project", gitRepo: nil, colorHex: "#0A84FF"
        )
        ctx.insert(project)

        let winner = TransitTask(
            name: "Winner Task", description: nil, type: .feature,
            project: project, displayID: .permanent(5)
        )
        winner.creationDate = now.addingTimeInterval(-600)
        winner.lastStatusChangeDate = now.addingTimeInterval(-600)
        winner.statusRawValue = TaskStatus.idea.rawValue
        ctx.insert(winner)

        let loser = TransitTask(
            name: "Loser Task", description: nil, type: .feature,
            project: project, displayID: .permanent(5)
        )
        loser.creationDate = now.addingTimeInterval(-300)
        loser.lastStatusChangeDate = now.addingTimeInterval(-300)
        loser.statusRawValue = TaskStatus.idea.rawValue
        ctx.insert(loser)

        // Milestone duplicates at the same display ID (5) as the task pair
        // above. Both milestone rows must remain visible in the reassignment
        // result list alongside the T-5 group. Without composite-key ForEach
        // identity (T-1062), one of them would be dropped by SwiftUI.
        let winnerMilestone = Milestone(
            name: "Winner Milestone", description: nil,
            project: project, displayID: .permanent(5)
        )
        winnerMilestone.creationDate = now.addingTimeInterval(-600)
        ctx.insert(winnerMilestone)

        let loserMilestone = Milestone(
            name: "Loser Milestone", description: nil,
            project: project, displayID: .permanent(5)
        )
        loserMilestone.creationDate = now.addingTimeInterval(-300)
        ctx.insert(loserMilestone)
    }
}
