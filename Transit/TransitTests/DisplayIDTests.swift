import Testing
@testable import Transit

struct DisplayIDTests {
    @Test
    func permanentDisplayIDFormatsAsTPrefixAndNumber() {
        #expect(DisplayID.permanent(42).formatted == "T-42")
        #expect(DisplayID.permanent(1).formatted == "T-1")
    }

    @Test
    func provisionalDisplayIDFormatsAsBullet() {
        #expect(DisplayID.provisional.formatted == "T-\u{2022}")
    }
}
