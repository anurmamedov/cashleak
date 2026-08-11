import XCTest
@testable import cashleak

/// Copy and projection rules that only revealed themselves once the app had
/// real data on screen.
///
/// Both bugs here were invisible on an empty database: the trade-off line read
/// "159% of your trip", and pace projected a month from nine days without
/// saying so.
final class OverviewCopyTests: XCTestCase {

    private let calendar = TestSupport.torontoCalendar

    // MARK: Pace

    /// Extrapolating a month from two days is arithmetically fine and
    /// practically nonsense — one grocery run on the 2nd projects a
    /// catastrophic month.
    func testPaceIsSuppressedInTheFirstWeek() {
        let summary = SpendingSummary(
            spent: 200, leaked: 50, kept: 150,
            transactionCount: 6, daysOfHistory: 3, pace: 3100, daysElapsed: 3
        )
        XCTAssertFalse(summary.paceIsMeaningful)
    }

    func testPaceAppearsAfterAWeek() {
        let summary = SpendingSummary(
            spent: 700, leaked: 200, kept: 500,
            transactionCount: 20, daysOfHistory: 7, pace: 3100, daysElapsed: 7
        )
        XCTAssertTrue(summary.paceIsMeaningful)
    }

    func testPaceIsNotMeaningfulWithNoSpend() {
        let summary = SpendingSummary(
            spent: 0, leaked: 0, kept: 0,
            transactionCount: 0, daysOfHistory: 20, pace: 0, daysElapsed: 20
        )
        XCTAssertFalse(summary.paceIsMeaningful)
    }

    func testEmptySummaryHasZeroElapsed() {
        XCTAssertEqual(SpendingSummary.empty.daysElapsed, 0)
        XCTAssertFalse(SpendingSummary.empty.paceIsMeaningful)
    }

    func testDaysElapsedIsPopulated() {
        let summary = SpendingSummary.make(
            from: [TestSupport.confirmed(50, verdict: .leak, date: .now)]
        )
        XCTAssertGreaterThanOrEqual(summary.daysElapsed, 1)
    }

    /// Pace projects forward, so it can never be below what's already spent.
    func testPaceNeverUndercutsActualSpend() {
        let summary = SpendingSummary.make(
            from: [TestSupport.confirmed(100, verdict: .worthIt, date: .now)]
        )
        XCTAssertGreaterThanOrEqual(summary.pace, summary.spent)
    }

    // MARK: Trade-off thresholds
    //
    // The view builds this string, so these tests pin the arithmetic that
    // decides which phrasing applies. Past 100% a percentage stops being a
    // trade-off and starts being arithmetic.

    func testShareBelowOneHundredUsesAPercentage() {
        let share = 412.0 / 1172.0
        XCTAssertLessThan(share, 1)
        XCTAssertEqual(Int((share * 100).rounded()), 35)
    }

    func testShareBetweenOneAndTwoReadsAsMoreThanTheWholeTrip() {
        let share = 301.0 / 189.0
        XCTAssertGreaterThanOrEqual(share, 1)
        XCTAssertLessThan(share, 2)
    }

    func testShareAboveTwoCountsWholeTrips() {
        let share = 600.0 / 189.0
        XCTAssertGreaterThanOrEqual(share, 2)
        XCTAssertEqual(Int(share.rounded(.down)), 3)
    }

    /// Rounding down matters: 2.9 trips is "2 trips", not "3". Overstating the
    /// trade-off would be the app exaggerating to make a point.
    func testTripCountRoundsDownNotNearest() {
        XCTAssertEqual(Int((2.9).rounded(.down)), 2)
        XCTAssertEqual(Int((2.1).rounded(.down)), 2)
    }
}
