import XCTest
@testable import cashleak

final class WidgetSnapshotTests: XCTestCase {

    private let now = TestSupport.date(2026, 8, 20, hour: 15)
    private let calendar = TestSupport.torontoCalendar

    func testTodayTotalIncludesOnlyConfirmedActiveTransactions() {
        let counted = TestSupport.confirmed(
            42, verdict: .worthIt, date: TestSupport.date(2026, 8, 20, hour: 10)
        )
        let yesterday = TestSupport.confirmed(
            100, verdict: .leak, date: TestSupport.date(2026, 8, 19, hour: 10)
        )
        let unconfirmed = Transaction(
            amount: 80, date: TestSupport.date(2026, 8, 20, hour: 11), source: .applePay
        )
        let superseded = TestSupport.confirmed(
            60, verdict: .leak, date: TestSupport.date(2026, 8, 20, hour: 12)
        )
        superseded.isSuperseded = true

        let snapshot = WidgetSnapshotBuilder.make(
            from: [counted, yesterday, unconfirmed, superseded],
            now: now,
            calendar: calendar,
            currencyCode: "CAD"
        )

        XCTAssertEqual(snapshot.todaySpent, 42)
        XCTAssertEqual(snapshot.unsortedCount, 1)
        XCTAssertEqual(snapshot.currencyCode, "CAD")
    }

    func testUnsortedCountIncludesAnyDayButExcludesSuperseded() {
        let old = Transaction(
            amount: 10, date: TestSupport.date(2026, 7, 1), source: .applePay
        )
        let duplicate = Transaction(amount: 10, date: now, source: .applePay)
        duplicate.isSuperseded = true

        let snapshot = WidgetSnapshotBuilder.make(
            from: [old, duplicate], now: now, calendar: calendar
        )
        XCTAssertEqual(snapshot.unsortedCount, 1)
    }

    func testYesterdayTotalBecomesZeroAtMidnight() {
        let snapshot = CashLeakWidgetSnapshot(
            todaySpent: 75,
            unsortedCount: 2,
            currencyCode: "CAD",
            updatedAt: TestSupport.date(2026, 8, 20, hour: 23, minute: 59)
        )

        XCTAssertEqual(
            snapshot.todaySpent(
                at: TestSupport.date(2026, 8, 21, hour: 0, minute: 1),
                calendar: calendar
            ),
            0
        )
        XCTAssertEqual(
            snapshot.todaySpent(
                at: TestSupport.date(2026, 8, 20, hour: 23, minute: 59),
                calendar: calendar
            ),
            75
        )
    }

    func testWidgetURLRoutesToSort() {
        XCTAssertEqual(URLRoute.destination(for: URL(string: "cashleak://sort")!), .sort)
    }

    func testForeignURLIsIgnored() {
        XCTAssertNil(URLRoute.destination(for: URL(string: "https://example.com/sort")!))
    }
}
