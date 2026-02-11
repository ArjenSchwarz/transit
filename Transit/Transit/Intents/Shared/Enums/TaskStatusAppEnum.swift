import AppIntents

extension TaskStatus: AppEnum {
    nonisolated public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Status")
    }

    nonisolated public static var caseDisplayRepresentations: [TaskStatus: DisplayRepresentation] {
        [
            .idea: "Idea",
            .planning: "Planning",
            .spec: "Spec",
            .readyForImplementation: "Ready for Implementation",
            .inProgress: "In Progress",
            .readyForReview: "Ready for Review",
            .done: "Done",
            .abandoned: "Abandoned"
        ]
    }
}
