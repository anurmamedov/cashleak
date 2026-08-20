import XCTest
@testable import cashleak

/// Week-over-week comparison and the tightened finding rules.
///
/// Every test here exists because a simulated two-week trial surfaced the
/// problem. None of them would have failed against an empty database.
final class WeekComparisonTests: XCTestCase {

    private let calendar = TestSupport.torontoCalendar
    /// A Thursday keeps all three fixture days inside their intended calendar
    /// weeks. Using the real current day made these tests fail on Sundays,
    /// Mondays and Tuesdays even though the production week gate was correct.
    private let now = TestSupport.date(2026, 8, 20)

    private func transaction(
        _ amount: Double,
        daysAgo: Int,
        verdict: Verdict,
        confirmed: Bool = true
    ) -> Transaction {
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return Transaction(
            amount: amount, date: date, merchant: "Test",
            source: .manual, verdict: verdict, isConfirmed: confirmed
        )
    }

    /// Enough transactions in both weeks, sitting either side of the week
    /// boundary. Offsets are relative to today, so the split lands wherever the
    /// current weekday puts it — hence the wide spread.
    private func twoWeeks(
        thisWeekLeakRatio: Double,
        lastWeekLeakRatio: Double
    ) -> [Transaction] {
        var result: [Transaction] = []

        for day in 0...2 {
            for index in 0..<4 {
                let isLeak = Double(index) / 4.0 < thisWeekLeakRatio
                result.append(transaction(25, daysAgo: day, verdict: isLeak ? .leak : .worthIt))
            }
        }
        for day in 9...11 {
            for index in 0..<4 {
                let isLeak = Double(index) / 4.0 < lastWeekLeakRatio
                result.append(transaction(25, daysAgo: day, verdict: isLeak ? .leak : .worthIt))
            }
        }
        return result
    }

    // MARK: Gating

    /// A comparison built on two transactions is noise. Better to say nothing.
    func testReturnsNilWithoutEnoughInEachWeek() {
        let sparse = [
            transaction(20, daysAgo: 0, verdict: .leak),
            transaction(20, daysAgo: 10, verdict: .leak),
        ]
        XCTAssertNil(AnalysisAggregates.weekOverWeek(sparse, now: now, calendar: calendar))
    }

    func testReturnsNilWhenLastWeekIsEmpty() {
        let onlyThisWeek = (0..<8).map { _ in transaction(20, daysAgo: 0, verdict: .leak) }
        XCTAssertNil(AnalysisAggregates.weekOverWeek(onlyThisWeek, now: now, calendar: calendar))
    }

    func testUnconfirmedAreExcluded() {
        var data = twoWeeks(thisWeekLeakRatio: 0.25, lastWeekLeakRatio: 0.5)
        data.append(transaction(9_000, daysAgo: 0, verdict: .leak, confirmed: false))

        guard let comparison = AnalysisAggregates.weekOverWeek(data, now: now, calendar: calendar) else {
            return XCTFail("expected a comparison")
        }
        // A 9,000 unconfirmed leak would swamp the ratio if it counted.
        XCTAssertLessThan(comparison.thisWeekRatio, 0.9)
    }

    // MARK: Direction

    /// The case the whole feature exists for: someone halves their leak and
    /// the month figure hides it.
    func testImprovementIsDetected() {
        guard let comparison = AnalysisAggregates.weekOverWeek(
            twoWeeks(thisWeekLeakRatio: 0.25, lastWeekLeakRatio: 0.75),
            now: now,
            calendar: calendar
        ) else { return XCTFail("expected a comparison") }

        XCTAssertTrue(comparison.isImprovement)
        XCTAssertLessThan(comparison.change, 0)
        XCTAssertGreaterThan(comparison.pointsChanged, 0)
    }

    func testRegressionIsDetected() {
        guard let comparison = AnalysisAggregates.weekOverWeek(
            twoWeeks(thisWeekLeakRatio: 0.75, lastWeekLeakRatio: 0.25),
            now: now,
            calendar: calendar
        ) else { return XCTFail("expected a comparison") }

        XCTAssertFalse(comparison.isImprovement)
        XCTAssertGreaterThan(comparison.change, 0)
    }

    func testPointsChangedIsPercentagePoints() {
        let comparison = AnalysisAggregates.WeekComparison(
            thisWeekRatio: 0.18, lastWeekRatio: 0.32,
            thisWeekLeaked: 90, lastWeekLeaked: 210
        )
        XCTAssertEqual(comparison.pointsChanged, 14)
        XCTAssertTrue(comparison.isImprovement)
    }

    // MARK: Weekday occurrences

    /// The bug the trial exposed: two Sundays in a fortnight isn't a pattern.
    func testWeekdayOccurrencesCountsRealDays() {
        let counts = AnalysisAggregates.weekdayOccurrences(in: .month, now: now, calendar: calendar)
        XCTAssertEqual(counts.values.reduce(0, +), calendar.component(.day, from: now))
        XCTAssertTrue(counts.values.allSatisfy { $0 >= 1 })
    }

    func testAveragePerOccurrenceDividesByRealDays() {
        let day = AnalysisAggregates.WeekdayTotal(weekday: 1, spent: 300, leaked: 100)
        XCTAssertEqual(day.averagePerOccurrence([1: 3]), 100, accuracy: 0.001)
        XCTAssertEqual(day.averagePerOccurrence([1: 0]), 0)
    }

    func testLeakShare() {
        XCTAssertEqual(
            AnalysisAggregates.WeekdayTotal(weekday: 2, spent: 200, leaked: 50).leakShare,
            0.25, accuracy: 0.001
        )
        XCTAssertEqual(
            AnalysisAggregates.WeekdayTotal(weekday: 2, spent: 0, leaked: 0).leakShare,
            0
        )
    }

    /// Two weeks of data must not produce a weekday claim — there are only two
    /// of each day, and "Sunday costs €333 more than Friday" was the result.
    func testNoWeekdayFindingFromATwoWeekTrial() {
        var data: [Transaction] = []
        for day in 0..<14 {
            for _ in 0..<2 {
                data.append(transaction(Double(20 + day * 3), daysAgo: day, verdict: day % 3 == 0 ? .leak : .worthIt))
            }
        }

        let finding = AnalysisAggregates.finding(data, range: .month, now: now, calendar: calendar)
        if let finding {
            XCTAssertFalse(
                finding.contains("more than a"),
                "weekday claim surfaced from only two weeks: \(finding)"
            )
        }
    }
}
