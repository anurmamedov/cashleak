import XCTest
@testable import cashleak

/// The take-home figure: quiet by default, one sentence only when something
/// happened, nothing at all when it isn't set (D-030).
final class TakeHomeTests: XCTestCase {

    private func summary(spent: Double, leaked: Double = 0, count: Int = 10, pace: Double? = nil, days: Int = 20) -> SpendingSummary {
        SpendingSummary(
            spent: spent, leaked: leaked, kept: spent - leaked,
            transactionCount: count, daysOfHistory: days,
            pace: pace ?? spent, daysElapsed: days
        )
    }

    private func overview(_ s: SpendingSummary, takeHome: Double = 5000, current: Bool = true, goal: Bool = false, day: Int = 20) -> TakeHome.OverviewLine? {
        TakeHome.overview(summary: s, takeHome: takeHome, isCurrentMonth: current, hasGoal: goal, monthName: "August", dayOfMonth: day)
    }

    // MARK: Not set

    func testNothingWhenNotSet() {
        XCTAssertNil(overview(summary(spent: 2000), takeHome: 0))
        XCTAssertNil(TakeHome.headlineShare(spent: 2000, monthsWithSpending: 1, takeHome: 0))
        XCTAssertNil(TakeHome.finding(monthBars: [], leaked: 500, sortedCount: 50, isYear: true, takeHome: 0))
    }

    // MARK: Overview

    /// A normal month: just the number, no sentence.
    func testQuietInAnOrdinaryMonth() throws {
        let line = try XCTUnwrap(overview(summary(spent: 2000, pace: 3000), goal: true))
        XCTAssertNil(line.sentence)
        XCTAssertEqual(line.label, "40% of take-home so far")
    }

    func testOverWinsOverEverythingElse() throws {
        let line = try XCTUnwrap(overview(summary(spent: 5214, leaked: 900)))
        XCTAssertTrue(line.sentence?.contains("over your take-home this month") == true)
        XCTAssertEqual(line.barShare, 1)
    }

    func testNearTheLimitByPace() throws {
        let line = try XCTUnwrap(overview(summary(spent: 3200, pace: 4800), goal: true))
        XCTAssertEqual(line.sentence, "On pace for 96% of your take-home.")
    }

    /// Leaks in days — only without a goal; the goal's line already does this.
    func testLeakDaysOnlyWithoutAGoal() throws {
        let s = summary(spent: 2000, leaked: 500, pace: 3000)
        XCTAssertTrue(try XCTUnwrap(overview(s, goal: false)).sentence?.contains("3 days of take-home") == true)
        XCTAssertNil(try XCTUnwrap(overview(s, goal: true)).sentence)
    }

    func testNoSentencesBeforeTheSeventh() throws {
        let line = try XCTUnwrap(overview(summary(spent: 4900, pace: 9000), day: 4))
        XCTAssertNil(line.sentence)
    }

    func testNoSentencesWithFewPurchases() throws {
        let line = try XCTUnwrap(overview(summary(spent: 5500, count: 3)))
        XCTAssertNil(line.sentence)
    }

    func testPastMonthSaysWhichMonth() throws {
        let line = try XCTUnwrap(overview(summary(spent: 5500), current: false, day: 2))
        XCTAssertTrue(line.sentence?.hasSuffix("over your take-home in August.") == true)
        XCTAssertEqual(line.label, "110% of take-home")
    }

    // MARK: Days

    func testDaysPhrase() {
        XCTAssertEqual(TakeHome.daysPhrase(0.9), "a day")
        XCTAssertEqual(TakeHome.daysPhrase(3.2), "3 days")
        XCTAssertEqual(TakeHome.daysPhrase(35), "about 5 weeks")
        XCTAssertEqual(TakeHome.days(500, of: 5000), 3, accuracy: 0.001)
    }

    // MARK: Analysis

    private func bars(_ amounts: [Double]) -> [AnalysisSummary.Bar] {
        amounts.enumerated().map { index, spent in
            let start = TestSupport.date(2026, 7 + index, 1)
            return AnalysisSummary.Bar(start: start, end: start, label: "", spent: spent, leaked: 0)
        }
    }

    func testAllMonthsUnder() {
        let line = TakeHome.finding(monthBars: bars([2000, 2100, 2200]), leaked: 100, sortedCount: 30, isYear: false, takeHome: 5000)
        XCTAssertEqual(line, "You spent less than your take-home in all 3 months.")
    }

    func testAllMonthsOverComesFirst() {
        let line = TakeHome.finding(monthBars: bars([5200, 5600]), leaked: 3000, sortedCount: 30, isYear: true, takeHome: 5000)
        XCTAssertEqual(line, "You spent more than your take-home in all 2 months.")
    }

    func testStandoutMonth() {
        let line = TakeHome.finding(monthBars: bars([1500, 1600, 3050]), leaked: 0, sortedCount: 30, isYear: false, takeHome: 5000)
        XCTAssertTrue(line?.contains("was your highest share: 61% of take-home") == true)
    }

    func testYearLeaksInWeeksOnlyOnYear() {
        let year = TakeHome.finding(monthBars: bars([2000, 2000]), leaked: 6000, sortedCount: 30, isYear: true, takeHome: 5000)
        XCTAssertEqual(year, "This year's leaks add up to about 5 weeks of take-home.")
        let quarter = TakeHome.finding(monthBars: bars([2000, 2000]), leaked: 6000, sortedCount: 30, isYear: false, takeHome: 5000)
        XCTAssertNotEqual(quarter, year)
    }

    func testHeadlineAveragesOverMonthsWithSpending() {
        XCTAssertEqual(TakeHome.headlineShare(spent: 6705, monthsWithSpending: 3, takeHome: 5200), "43% of take-home")
    }
}
