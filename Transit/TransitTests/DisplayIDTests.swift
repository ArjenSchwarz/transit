//
//  DisplayIDTests.swift
//  TransitTests
//
//  Tests for DisplayID enum formatting.
//

import Testing
@testable import Transit

@MainActor
struct DisplayIDTests {
    @Test func permanentIDFormatsWithNumber() {
        #expect(DisplayID.permanent(1).formatted == "T-1")
        #expect(DisplayID.permanent(42).formatted == "T-42")
        #expect(DisplayID.permanent(999).formatted == "T-999")
    }

    @Test func provisionalIDFormatsWithBullet() {
        #expect(DisplayID.provisional.formatted == "T-•")
    }

    @Test func displayIDEquality() {
        #expect(DisplayID.permanent(1) == DisplayID.permanent(1))
        #expect(DisplayID.permanent(1) != DisplayID.permanent(2))
        #expect(DisplayID.provisional == DisplayID.provisional)
        #expect(DisplayID.permanent(1) != DisplayID.provisional)
    }
}
