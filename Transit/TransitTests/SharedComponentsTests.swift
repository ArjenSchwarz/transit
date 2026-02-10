import Foundation
import Testing
@testable import Transit

@MainActor
struct SharedComponentsTests {
    @Test
    func typeBadgeTitlesAndTintHexMapPerType() {
        #expect(TaskType.bug.badgeTitle == "Bug")
        #expect(TaskType.feature.badgeTitle == "Feature")
        #expect(TaskType.chore.badgeTitle == "Chore")
        #expect(TaskType.research.badgeTitle == "Research")
        #expect(TaskType.documentation.badgeTitle == "Docs")

        #expect(TaskType.bug.badgeTintHex == "C2410C")
        #expect(TaskType.feature.badgeTintHex == "005BC5")
        #expect(TaskType.chore.badgeTintHex == "4A4A4A")
        #expect(TaskType.research.badgeTintHex == "7A3E9D")
        #expect(TaskType.documentation.badgeTintHex == "0B7A57")
    }

    @Test
    func metadataDraftBuildsSortedEntries() {
        let entries = MetadataDraft.makeEntries(from: [
            "zeta": "3",
            "alpha": "1",
            "Beta": "2"
        ])

        #expect(entries.map { $0.key } == ["alpha", "Beta", "zeta"])
    }

    @Test
    func metadataDraftMaterializeTrimsAndDropsEmptyKeys() {
        let entries = [
            MetadataEntry(id: UUID(), key: " owner ", value: " orbit "),
            MetadataEntry(id: UUID(), key: "", value: "discard"),
            MetadataEntry(id: UUID(), key: "   ", value: "discard"),
            MetadataEntry(id: UUID(), key: "ticket", value: " T-42")
        ]

        let metadata = MetadataDraft.materialize(entries: entries)

        #expect(metadata?["owner"] == "orbit")
        #expect(metadata?["ticket"] == "T-42")
        #expect(metadata?[""] == nil)
        #expect(metadata?.count == 2)
    }

    @Test
    func metadataDraftMaterializeReturnsNilWhenNoValidEntriesRemain() {
        let entries = [
            MetadataEntry(id: UUID(), key: " ", value: "value")
        ]

        #expect(MetadataDraft.materialize(entries: entries) == nil)
        #expect(MetadataDraft.materialize(entries: []) == nil)
    }
}
