import Foundation
import Testing
@testable import Transit

@MainActor
struct DateTransitHelpersTests {
    // MARK: - isWithin48Hours

    @Test func dateWithin48HoursReturnsTrue() {
        let now = Date.now
        let oneHourAgo = now.addingTimeInterval(-1 * 60 * 60)
        #expect(oneHourAgo.isWithin48Hours(of: now))
    }

    @Test func dateExactly48HoursAgoReturnsTrue() {
        let now = Date.now
        let exactly48h = now.addingTimeInterval(-48 * 60 * 60)
        #expect(exactly48h.isWithin48Hours(of: now))
    }

    @Test func dateOlderThan48HoursReturnsFalse() {
        let now = Date.now
        let moreThan48h = now.addingTimeInterval(-49 * 60 * 60)
        #expect(!moreThan48h.isWithin48Hours(of: now))
    }

    @Test func sameDateReturnsTrue() {
        let now = Date.now
        #expect(now.isWithin48Hours(of: now))
    }

    // T-136: Future dates must NOT be considered within 48 hours
    @Test func futureDateReturnsFalse() {
        let now = Date.now
        let oneHourFromNow = now.addingTimeInterval(1 * 60 * 60)
        #expect(!oneHourFromNow.isWithin48Hours(of: now),
                "A future date should not be considered within the last 48 hours")
    }

    // T-136: Even a date just 1 second in the future should be rejected
    @Test func dateOneSecondInFutureReturnsFalse() {
        let now = Date.now
        let justAhead = now.addingTimeInterval(1)
        #expect(!justAhead.isWithin48Hours(of: now),
                "A date 1 second in the future should not be within the last 48 hours")
    }

    // T-136: A date far in the future should also be rejected
    @Test func dateFarInFutureReturnsFalse() {
        let now = Date.now
        let nextWeek = now.addingTimeInterval(7 * 24 * 60 * 60)
        #expect(!nextWeek.isWithin48Hours(of: now),
                "A date 7 days in the future should not be within the last 48 hours")
    }
}
