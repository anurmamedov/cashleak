import XCTest
@testable import cashleak

/// The two lists on the redesigned Overview: every category's spending for the
/// month, and what was bought today.
///
/// Both exist because the old screen hid things. Leaks-only categories meant a
/// coffee marked worth it appeared nowhere; totals-only meant a capture still
/// in Sort couldn't be seen at all. These pin down that nothing disappears.
final class CategorySpendTests: XCTestCase {

    // MARK: By category

    /// The case that prompted the redesign: coffee marked worth it must show.
    func testWorthItSpendingIsIncluded() {
        let coffee = cashleak.Category(name: "Coffee")
        let rows = SpendingSummary.byCategory(from: [
            TestSupport.confirmed(4.19, verdict: .worthIt, category: coffee),
            TestSupport.confirmed(6.25, verdict: .worthIt, category: coffee),
        ])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "Coffee")
        XCTAssertEqual(rows[0].total, 10.44, accuracy: 0.001)
        XCTAssertEqual(rows[0].leaked, 0, accuracy: 0.001)
        XCTAssertEqual(rows[0].count, 2)
    }

    func testLeakedShareIsCarriedInsideTheCategory() {
        let dining = cashleak.Category(name: "Dining out")
        let rows = SpendingSummary.byCategory(from: [
            TestSupport.confirmed(80, verdict: .leak, category: dining),
            TestSupport.confirmed(50, verdict: .worthIt, category: dining),
        ])

        XCTAssertEqual(rows[0].total, 130, accuracy: 0.001)
        XCTAssertEqual(rows[0].leaked, 80, accuracy: 0.001)
    }

    func testOrderedByTotalLargestFirst() {
        let groceries = cashleak.Category(name: "Groceries")
        let coffee = cashleak.Category(name: "Coffee")
        let rows = SpendingSummary.byCategory(from: [
            TestSupport.confirmed(6, verdict: .leak, category: coffee),
            TestSupport.confirmed(120, verdict: .worthIt, category: groceries),
        ])
        XCTAssertEqual(rows.map(\.name), ["Groceries", "Coffee"])
    }

    func testUncategorisedGetsItsOwnRow() {
        let rows = SpendingSummary.byCategory(from: [
            TestSupport.confirmed(12, verdict: .leak)
        ])
        XCTAssertEqual(rows.first?.name, "Uncategorised")
    }

    /// Totals only ever count what a person has confirmed.
    func testUnsortedAndSupersededAreExcluded() {
        let coffee = cashleak.Category(name: "Coffee")
        let unsorted = Transaction(amount: 4.19, merchant: "Tim Hortons", category: coffee)
        let superseded = TestSupport.confirmed(9, verdict: .leak, category: coffee)
        superseded.isSuperseded = true

        XCTAssertTrue(SpendingSummary.byCategory(from: [unsorted, superseded]).isEmpty)
    }

    func testOtherMonthsAreExcluded() {
        let coffee = cashleak.Category(name: "Coffee")
        let lastYear = Calendar.current.date(byAdding: .year, value: -1, to: .now)!
        let rows = SpendingSummary.byCategory(from: [
            TestSupport.confirmed(4, verdict: .leak, date: lastYear, category: coffee)
        ])
        XCTAssertTrue(rows.isEmpty)
    }

    // MARK: Today

    /// A capture still in Sort must appear in today's list — "did my coffee
    /// register?" is the question this list answers.
    func testTodayIncludesUnsortedCaptures() {
        let now = Date.now
        let unsorted = Transaction(amount: 4.19, date: now, merchant: "Tim Hortons", source: .applePay)
        let sorted = TestSupport.confirmed(44.65, verdict: .worthIt, date: now, merchant: "No Frills")

        let today = SpendingSummary.purchases(on: now, from: [unsorted, sorted])
        XCTAssertEqual(today.count, 2)
    }

    func testTodayExcludesOtherDaysAndSuperseded() {
        let now = Date.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let old = TestSupport.confirmed(10, verdict: .leak, date: yesterday)
        let merged = TestSupport.confirmed(10, verdict: .leak, date: now)
        merged.isSuperseded = true

        XCTAssertTrue(SpendingSummary.purchases(on: now, from: [old, merged]).isEmpty)
    }

    func testTodayIsNewestFirst() {
        let now = Date.now
        let calendar = Calendar.current
        let morning = calendar.date(bySettingHour: 0, minute: 5, second: 0, of: now)!
        let later = calendar.date(bySettingHour: 0, minute: 30, second: 0, of: now)!

        let today = SpendingSummary.purchases(on: now, from: [
            TestSupport.confirmed(1, verdict: .leak, date: morning, merchant: "First"),
            TestSupport.confirmed(2, verdict: .leak, date: later, merchant: "Second"),
        ])
        XCTAssertEqual(today.map(\.merchant), ["Second", "First"])
    }
}
