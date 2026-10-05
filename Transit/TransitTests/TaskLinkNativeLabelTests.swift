import Foundation
import Testing
@testable import Transit

@MainActor struct TaskLinkNativeLabelTests {
    @Test(arguments: [
        "dependency|false|Blocks", "dependency|true|Blocked by",
        "association|false|Relates to", "association|true|Relates to",
        "attribution|false|Introduced by", "attribution|true|Introduces",
        "duplicate|false|Duplicate of", "duplicate|true|Duplicated by",
        "future/raw-kind|false|Unknown relation", "future/raw-kind|true|Unknown relation"
    ])
    func labelsAreRelativeToSelectedEndpoint(contract: String) throws {
        let parts = contract.split(separator: "|").map(String.init)
        try #require(parts.count == 3)
        #expect(TaskLinkNativeLabels.title(kind: parts[0], incoming: parts[1] == "true") == parts[2])
    }
}
