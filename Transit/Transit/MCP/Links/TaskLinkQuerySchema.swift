#if os(macOS)
import Foundation

nonisolated enum TaskLinkQuerySchema {
    static let properties: [String: JSONSchemaProperty] = [
        "hasLinks": .boolean("Recorded active incidence, including invalid physical occurrences"),
        "linkType": .stringEnum("Require a valid incident relation in this public orientation",
                                    values: TaskLinkType.allCases.map(\.rawValue)),
        "linkDirection": .stringEnum("Only introduced-by/duplicate-of; defaults outgoing; requires linkType",
                                         values: ["incoming", "outgoing"]),
        "linkTargetTaskId": .string("Opposite endpoint UUID; requires linkType; never follows duplicate aliases"),
        "unblocked": .boolean("True: certified unblocked; false: certified blocked; invalid/unavailable match neither")
    ]

    static let guidance = """
    Graph options apply conjunctively to ordinary list/displayId selection before ordering and pagination.
    UUID/display-ID batch selectors retain their existing no-filter contract. Reusable snapshot queries reject
    graph options. blocks is outgoing dependency; blocked-by is incoming dependency; relates-to is symmetric.
    Direction is supported only for introduced-by and duplicate-of. Type/target filters match valid occurrences;
    hasLinks includes recorded invalid rows. Only Done direct blockers are satisfied; Abandoned is blocked.
    Missing, ambiguous, cyclic or invalid blocker evidence certifies neither unblocked value. Duplicate paths do
    not redirect selection or flatten stored occurrences. Full detail includes links with edgeId, exact
    occurrenceRevision when identifiable, stored endpoints, public type, direction, saved opposite targetName
    and physicalIdentity; linkDiagnostics preserve available physical conflicts. duplicateResolution contains
    path, canonicalTaskId or null and diagnostic; blockerAssessment supplies assessment and evaluatedAt. All
    observation fields use the same frozen saved capture as the record; UI drafts are never returned. Current
    full revisions cover fields, all comments and active incidence (task-fields-comments-links-v1), including
    empty incidence. Labels, blocker status, transitive paths and removal retention are observation evidence
    outside that token. Pre-feature r1 tokens conflict on fresh writes even for no-link tasks. Omitted bodies do
    not imply empty incidence. Missing historic graph capture reports graphCoverage unavailable with null link
    observations; accepted historic receipt bytes and revisions remain immutable. Protection covers
    participating local writes, not independent imports or writers.
    """
}
#endif
