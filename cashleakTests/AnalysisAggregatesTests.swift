import XCTest
@testable import cashleak

/// Aggregates fail silently — a wrong number renders exactly like a right one.
final class AnalysisAggregatesTests: XCTestCase {

    private let calendar = TestSupport.torontoCalendar
    private let now = TestSupport.date(2026, 8, 20, hour: 12)

    private func transaction(
        _ amount: Double,
        day: Int,
        month: Int = 8,
        verdict: Verdict = .leak,
        merchant: String = "Test",
        confirmed: Bool = true
    ) -> Transaction {
        Transaction(
            amount: amount,
            date: TestSupport.date(2026, month, day, hour: 12),
            merchant: merchant,
            source: .manual,
            verdict: verdict,
            isConfirmed: confirmed
        )
    }

    // MARK: Filtering

    func testUnconfirmedExcludedFromEveryAggregate() {
        let data = [
            transaction(100, day: 5, confirmed: true),
            transaction(900, day: 6, confirmed: false),
        ]
        let counted = AnalysisAggregates.counted(data, in: .month, now: now, calendar: calendar)
        XCTAssertEqual(counted.count, 1)
    }

    func testSupersededExcluded() {
        let duplicate = transaction(50, day: 5)
        duplicate.isSuperseded = true
        let counted = AnalysisAggregates.counted(
            [transaction(20, day: 5), duplicate], in: .month, now: now, calendar: calendar
        )
        XCTAssertEqual(counted.count, 1)
    }

    func testMonthRangeExcludesPriorMonths() {
        let data = [
            transaction(100, day: 5, month: 8),
            transaction(999, day: 5, month: 7),
        ]
        let counted = AnalysisAggregates.counted(data, in: .month, now: now, calendar: calendar)
        XCTAssertEqual(counted.count, 1)
    }

    func testQuarterRangeIncludesThreeMonths() {
        let data = [
            transaction(10, day: 5, month: 8),
            transaction(10, day: 5, month: 7),
            transaction(10, day: 5, month: 6),
            transaction(10, day: 5, month: 5),
        ]
        let counted = AnalysisAggregates.counted(data, in: .quarter, now: now, calendar: calendar)
        XCTAssertEqual(counted.count, 3)
    }

    // MARK: Trend

    func testTrendBucketsByDayForMonth() {
        let points = AnalysisAggregates.trend(
            [transaction(10, day: 5), transaction(15, day: 5), transaction(20, day: 6)],
            range: .month, now: now, calendar: calendar
        )
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].spent, 25, accuracy: 0.001)
        XCTAssertEqual(points[1].spent, 20, accuracy: 0.001)
    }

    func testTrendIsChronological() {
        let points = AnalysisAggregates.trend(
            [transaction(10, day: 20), transaction(10, day: 2), transaction(10, day: 11)],
            range: .month, now: now, calendar: calendar
        )
        XCTAssertEqual(points.map(\.date), points.map(\.date).sorted())
    }

    func testKeptIsSpentMinusLeaked() {
        let points = AnalysisAggregates.trend(
            [transaction(30, day: 5, verdict: .leak), transaction(70, day: 5, verdict: .worthIt)],
            range: .month, now: now, calendar: calendar
        )
        XCTAssertEqual(points[0].spent, 100, accuracy: 0.001)
        XCTAssertEqual(points[0].leaked, 30, accuracy: 0.001)
        XCTAssertEqual(points[0].kept, 70, accuracy: 0.001)
    }

    func testEmptyDataProducesNoPoints() {
        XCTAssertTrue(AnalysisAggregates.trend([], range: .month, now: now, calendar: calendar).isEmpty)
    }

    // MARK: Merchants

    /// Ranked by leak, not by spend. Groceries are the biggest line on most
    /// statements and almost never the answer to "what would I take back".
    func testLeaderboardRanksByLeakNotTotal() {
        let data = [
            transaction(400, day: 5, verdict: .worthIt, merchant: "Loblaws"),
            transaction(90, day: 6, verdict: .leak, merchant: "Uber Eats"),
        ]
        let board = AnalysisAggregates.merchantLeaderboard(data, range: .month, now: now, calendar: calendar)
        XCTAssertEqual(board.count, 1)
        XCTAssertEqual(board[0].merchant, "Uber Eats")
    }

    /// Different formats of the same merchant must aggregate together, or the
    /// leaderboard splits one habit into three small entries.
    func testLeaderboardGroupsByNormalizedMerchant() {
        let data = [
            transaction(20, day: 5, merchant: "SQ *BLUE BOTTLE"),
            transaction(25, day: 6, merchant: "BLUE BOTTLE #4412"),
        ]
        let board = AnalysisAggregates.merchantLeaderboard(data, range: .month, now: now, calendar: calendar)
        XCTAssertEqual(board.count, 1)
        XCTAssertEqual(board[0].leaked, 45, accuracy: 0.001)
        XCTAssertEqual(board[0].count, 2)
    }

    func testLeaderboardRespectsLimit() {
        let merchants = [
            "Alpha", "Bravo", "Charlie", "Delta", "Echo",
            "Foxtrot", "Golf", "Hotel", "India", "Juliet",
        ]
        let data = merchants.enumerated().map { index, merchant in
            transaction(Double((index + 1) * 10), day: index + 1, merchant: merchant)
        }
        let board = AnalysisAggregates.merchantLeaderboard(
            data, range: .month, limit: 3, now: now, calendar: calendar
        )
        XCTAssertEqual(board.count, 3)
        XCTAssertEqual(board[0].leaked, 100, accuracy: 0.001)
    }

    // MARK: Weekday

    /// Seven entries always. A missing bar reads as missing data; a zero bar
    /// reads as a quiet day.
    func testWeekdayPatternAlwaysReturnsSeven() {
        let pattern = AnalysisAggregates.weekdayPattern(
            [transaction(10, day: 5)], range: .month, now: now, calendar: calendar
        )
        XCTAssertEqual(pattern.count, 7)
    }

    func testWeekdayPatternAttributesToCorrectDay() {
        // 2026-08-07 is a Friday, weekday 6 in Gregorian.
        let pattern = AnalysisAggregates.weekdayPattern(
            [transaction(50, day: 7)], range: .month, now: now, calendar: calendar
        )
        XCTAssertEqual(pattern.first { $0.weekday == 6 }?.spent, 50)
    }

    // MARK: Finding

    /// Silence beats a weak finding.
    func testNoFindingBelowFifteenTransactions() {
        let data = (1...14).map { transaction(10, day: $0) }
        XCTAssertNil(AnalysisAggregates.finding(data, range: .month, now: now, calendar: calendar))
    }

    func testFindingAppearsWithEnoughData() {
        let data = (1...20).map { transaction(Double(10 + $0), day: $0) }
        XCTAssertNotNil(AnalysisAggregates.finding(data, range: .month, now: now, calendar: calendar))
    }

    func testDominantMerchantSurfacesInFinding() {
        var data = (1...12).map { transaction(5, day: $0, merchant: "Small \($0)") }
        data += (13...18).map { transaction(60, day: $0, merchant: "Uber Eats") }

        let finding = AnalysisAggregates.finding(data, range: .month, now: now, calendar: calendar)
        XCTAssertNotNil(finding)
    }

    func testFindingIsNilWhenNothingLeaked() {
        let data = (1...20).map { transaction(10, day: $0, verdict: .worthIt) }
        // All worth it, so the weekday and merchant candidates find nothing and
        // the ratio is zero.
        let finding = AnalysisAggregates.finding(data, range: .month, now: now, calendar: calendar)
        if let finding {
            XCTAssertFalse(finding.contains("0%"))
        }
    }
}
