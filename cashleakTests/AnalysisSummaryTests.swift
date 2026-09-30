import XCTest
@testable import cashleak

/// The redesigned Analysis screen's numbers.
///
/// Each of these is a way the screen could mislead while looking fine: a month
/// compared against a whole previous month, a rent week flattening the chart,
/// a "habit" read off six purchases.
final class AnalysisSummaryTests: XCTestCase {

    private let calendar = TestSupport.torontoCalendar

    private func on(_ month: Int, _ day: Int, _ amount: Double, _ verdict: Verdict = .worthIt,
                    merchant: String = "Shop", category: cashleak.Category? = nil) -> Transaction {
        TestSupport.confirmed(amount, verdict: verdict,
                              date: TestSupport.date(2026, month, day, calendar: calendar),
                              merchant: merchant, category: category)
    }

    private var sep15: Date { TestSupport.date(2026, 9, 15, hour: 18, calendar: calendar) }

    // MARK: Comparison

    /// Half of September against the first half of August — not all of it.
    func testMonthComparesAgainstTheSamePointLastMonth() {
        let transactions = [
            on(8, 10, 100),   // inside August's first half
            on(8, 25, 900),   // after the same point — must be ignored
            on(9, 5, 150),
        ]
        let headline = AnalysisSummary.headline(transactions, range: .month, now: sep15, calendar: calendar)
        // Currency symbol depends on locale; the words and the 50 don't.
        XCTAssertTrue(headline.context?.hasPrefix("↑") == true)
        XCTAssertTrue(headline.context?.contains("50 more than this time in August") == true,
                      headline.context ?? "nil")
    }

    func testNoComparisonWithoutLastMonthData() {
        let headline = AnalysisSummary.headline([on(9, 5, 150)], range: .month, now: sep15, calendar: calendar)
        XCTAssertNil(headline.context)
    }

    func testHeadlineSplitsLeakedAndWorthIt() {
        let headline = AnalysisSummary.headline(
            [on(9, 2, 40, .leak), on(9, 3, 60, .worthIt)],
            range: .month, now: sep15, calendar: calendar
        )
        XCTAssertEqual(headline.spent, 100, accuracy: 0.001)
        XCTAssertEqual(headline.leaked, 40, accuracy: 0.001)
        XCTAssertEqual(headline.kept, 60, accuracy: 0.001)
    }

    // MARK: Bars

    /// A month is weeks, never days, and stops at today.
    func testMonthBarsAreWeeksUpToToday() {
        let bars = AnalysisSummary.bars([on(9, 2, 20)], range: .month, now: sep15, calendar: calendar)
        XCTAssertTrue(bars.count >= 3 && bars.count <= 4, "Sep 1–15 spans three or four weeks, got \(bars.count)")
        XCTAssertTrue(bars.allSatisfy { $0.start <= sep15 })
        XCTAssertEqual(bars.reduce(0) { $0 + $1.spent }, 20, accuracy: 0.001)
    }

    /// Twelve months always, including empty ones, so the axis doesn't jump.
    func testYearHasTwelveBarsIncludingEmptyMonths() {
        let bars = AnalysisSummary.bars([on(9, 2, 20)], range: .year, now: sep15, calendar: calendar)
        XCTAssertEqual(bars.count, 12)
        XCTAssertEqual(bars.filter { $0.spent > 0 }.count, 1)
    }

    func testQuarterHasThreeBars() {
        XCTAssertEqual(AnalysisSummary.bars([], range: .quarter, now: sep15, calendar: calendar).count, 3)
    }

    /// Rent in week one mustn't flatten the other weeks.
    func testOutlierIsCapped() {
        let bars = [1697.0, 87, 207, 820].enumerated().map { index, spent in
            AnalysisSummary.Bar(start: Date(timeIntervalSince1970: Double(index)), end: .now,
                                label: "", spent: spent, leaked: 0)
        }
        let result = AnalysisSummary.chartCeiling(for: bars)
        XCTAssertFalse(result.isCapped, "1697 is only about 2x 820 — no cap")

        let skewed = [3000.0, 87, 207, 820].enumerated().map { index, spent in
            AnalysisSummary.Bar(start: Date(timeIntervalSince1970: Double(index)), end: .now,
                                label: "", spent: spent, leaked: 0)
        }
        let capped = AnalysisSummary.chartCeiling(for: skewed)
        XCTAssertTrue(capped.isCapped)
        XCTAssertEqual(capped.ceiling, 820 * 1.3, accuracy: 0.001)
    }

    // MARK: Findings

    /// Facts are arithmetic and show from the start.
    func testFactsAppearWithFewPurchases() {
        let coffee = cashleak.Category(name: "Coffee")
        let transactions = [
            on(8, 5, 30),
            on(9, 2, 5, .leak, merchant: "Tim Hortons", category: coffee),
            on(9, 3, 5, .leak, merchant: "Tim Hortons", category: coffee),
            on(9, 9, 5, .leak, merchant: "Tim Hortons", category: coffee),
        ]
        let findings = AnalysisSummary.findings(transactions, range: .month, now: sep15, calendar: calendar)
        XCTAssertFalse(findings.isEmpty)
        XCTAssertTrue(findings.allSatisfy { $0.kind == .fact })
        XCTAssertTrue(findings.contains { $0.text.contains("Tim Hortons") })
    }

    /// Patterns wait for 15 sorted purchases.
    func testNoPatternsBelowThreshold() {
        let transactions = (1...14).map { on(9, min($0, 15), 10, .leak) }
        let findings = AnalysisSummary.findings(transactions, range: .month, now: sep15, calendar: calendar)
        XCTAssertFalse(findings.contains { $0.kind == .pattern })
    }

    func testNothingToSayWithNoData() {
        XCTAssertTrue(AnalysisSummary.findings([], range: .month, now: sep15, calendar: calendar).isEmpty)
    }
}
