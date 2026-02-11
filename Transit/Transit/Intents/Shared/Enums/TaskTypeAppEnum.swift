import AppIntents

extension TaskType: AppEnum {
    nonisolated public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Type")
    }

    nonisolated public static var caseDisplayRepresentations: [TaskType: DisplayRepresentation] {
        [
            .bug: "Bug",
            .feature: "Feature",
            .chore: "Chore",
            .research: "Research",
            .documentation: "Documentation"
        ]
    }
}
