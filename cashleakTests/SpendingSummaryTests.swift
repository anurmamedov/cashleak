import XCTest
@testable import cashleak

/// Aggregates are invisible when wrong — the number renders, it just isn't
/// true. That makes them worth testing more than anything with a visible
/// failure mode.
final class SpendingSummaryTests: XCTestCase {

    private var thisMonth: Date { Date.now }

    // MARK: Counting rules

    /// The invariant from DECISIONS.md: an unconfirmed record is a claim from a
    /// parser, not a fact. It must never reach a total.
    func testUnconfirmedTransactionsAreExcluded() {
        let transactions = [
            TestSupport.confirmed(100, verdict: .leak),
            Transaction(amount: 500, date: .now, source: .applePay, isConfirmed: false),
        ]

        let summary = SpendingSummary.make(from: transactions)

        XCTAssertEqual(summary.spent, 100, accuracy: 0.001)
        XCTAssertEqual(summary.transactionCount, 1)
    }

    func testSupersededTransactionsAreExcluded() {
        let duplicate = TestSupport.confirmed(100, verdict: .leak)
        duplicate.isSuperseded = true

        let summary = SpendingSummary.make(from: [
            TestSupport.confirmed(40, verdict: .worthIt),
            duplicate,
        ])

        XCTAssertEqual(summary.spent, 40, accuracy: 0.001)
    }

    func testUnratedCountsTowardSpentButNeitherVerdictBucket() {
        let summary = SpendingSummary.make(from: [
            TestSupport.confirmed(30, verdict: .unrated),
            TestSupport.confirmed(70, verdict: .leak),
        ])

        XCTAssertEqual(summary.spent, 100, accuracy: 0.001)
        XCTAssertEqual(summary.leaked, 70, accuracy: 0.001)
        XCTAssertEqual(summary.kept, 0, accuracy: 0.001)
    }

    // MARK: Ratio

    func testLeakRatio() {
        let summary = SpendingSummary.make(from: [
            TestSupport.confirmed(75, verdict: .worthIt),
            TestSupport.confirmed(25, verdict: .leak),
        ])
        XCTAssertEqual(summary.leakRatio, 0.25, accuracy: 0.001)
    }

    /// No transactions must mean a ratio of zero, not a crash and not NaN.
    func testEmptyDataHasZeroRatio() {
        let summary = SpendingSummary.make(from: [])
        XCTAssertEqual(summary.leakRatio, 0)
        XCTAssertFalse(summary.leakRatio.isNaN)
        XCTAssertEqual(summary.transactionCount, 0)
    }

    func testAllLeakGivesRatioOfOne() {
        let summary = SpendingSummary.make(from: [
            TestSupport.confirmed(50, verdict: .leak)
        ])
        XCTAssertEqual(summary.leakRatio, 1.0, accuracy: 0.001)
    }

    // MARK: Month boundaries

    func testTransactionsOutsideTheMonthAreExcluded() {
        let calendar = Calendar.current
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: .now)!

        let summary = SpendingSummary.make(from: [
            TestSupport.confirmed(100, verdict: .leak, date: .now),
            TestSupport.confirmed(999, verdict: .leak, date: lastMonth),
        ])

        XCTAssertEqual(summary.spent, 100, accuracy: 0.001)
    }

    // MARK: Pace

    func testPaceProjectsForward() {
        let summary = SpendingSummary.make(from: [
            TestSupport.confirmed(100, verdict: .worthIt)
        ])
        // Pace extrapolates the daily rate across the month, so it can only be
        // greater than or equal to what's been spent so far.
        XCTAssertGreaterThanOrEqual(summary.pace, summary.spent)
    }

    // MARK: Breakdown

    func testLeaksByCategoryOrdersByTotalDescending() {
        let dining = cashleak.Category(name: "Dining out")
        let coffee = cashleak.Category(name: "Coffee")

        let rows = SpendingSummary.leaksByCategory(from: [
            TestSupport.confirmed(20, verdict: .leak, category: coffee),
            TestSupport.confirmed(80, verdict: .leak, category: dining),
            TestSupport.confirmed(50, verdict: .worthIt, category: dining),
        ])

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].category?.name, "Dining out")
        XCTAssertEqual(rows[0].total, 80, accuracy: 0.001)
        XCTAssertEqual(rows[1].total, 20, accuracy: 0.001)
    }

    func testLeaksByCategoryIgnoresWorthItEntirely() {
        let rows = SpendingSummary.leaksByCategory(from: [
            TestSupport.confirmed(500, verdict: .worthIt, category: cashleak.Category(name: "Rent"))
        ])
        XCTAssertTrue(rows.isEmpty)
    }
}
