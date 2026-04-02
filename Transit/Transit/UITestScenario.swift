import Foundation
import SwiftData

enum UITestScenario: String {
    case empty
    case board

    // swiftlint:disable:next function_body_length
    func seed(into ctx: ModelContext) {
        switch self {
        case .empty:
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
}
