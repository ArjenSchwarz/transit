import Testing
@testable import Transit

@MainActor
struct DisplayIDTests {

    @Test func permanentIDFormatsWithPrefix() {
        let id = DisplayID.permanent(42)
        #expect(id.formatted == "T-42")
    }

    @Test func permanentIDFormatsWithSmallNumber() {
        let id = DisplayID.permanent(1)
        #expect(id.formatted == "T-1")
    }

    @Test func provisionalIDFormatsAsBullet() {
        let id = DisplayID.provisional
        #expect(id.formatted == "T-\u{2022}")
    }

    @Test func permanentIDsAreEqual() {
        #expect(DisplayID.permanent(5) == DisplayID.permanent(5))
    }

    @Test func differentPermanentIDsAreNotEqual() {
        #expect(DisplayID.permanent(5) != DisplayID.permanent(6))
    }

    @Test func provisionalIDsAreEqual() {
        #expect(DisplayID.provisional == DisplayID.provisional)
    }

    @Test func permanentAndProvisionalAreNotEqual() {
        #expect(DisplayID.permanent(1) != DisplayID.provisional)
    }

    // MARK: - formatted(prefix:)

    @Test func formattedWithMilestonePrefixReturnsMDash() {
        let id = DisplayID.permanent(3)
        #expect(id.formatted(prefix: "M") == "M-3")
    }

    @Test func provisionalWithMilestonePrefixReturnsBullet() {
        let id = DisplayID.provisional
        #expect(id.formatted(prefix: "M") == "M-\u{2022}")
    }

    @Test func formattedPropertyStillReturnsTaskPrefix() {
        let id = DisplayID.permanent(42)
        #expect(id.formatted == "T-42")
    }

    @Test func formattedWithTaskPrefixMatchesProperty() {
        let id = DisplayID.permanent(7)
        #expect(id.formatted == id.formatted(prefix: "T"))
    }
}
