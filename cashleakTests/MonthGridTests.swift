import XCTest
@testable import cashleak

/// The month picker's cells (D-040).
@MainActor
final class MonthGridTests: XCTestCase {

    private let calendar = TestSupport.torontoCalendar

    private func month(_ year: Int, _ month: Int) -> Date {
        TestSupport.date(year, month, 1, hour: 0, calendar: calendar)
    }

    func testTwelveCellsPerYearNewestYearFirst() {
        let available = [month(2025, 11), month(2025, 12), month(2026, 1)]
        let years = MonthGrid.years([], available: available, calendar: calendar)
        XCTAssertEqual(years.map(\.year), [2026, 2025])
        XCTAssertEqual(years.map { $0.cells.count }, [12, 12])
    }

    func testOnlyMonthsInRangeCanBeOpened() {
        let available = [month(2026, 9), month(2026, 10)]
        let year = MonthGrid.years([], available: available, calendar: calendar)[0]
        XCTAssertEqual(year.cells.filter(\.isAvailable).count, 2)
        XCTAssertFalse(year.cells[7].isAvailable)   // August
        XCTAssertTrue(year.cells[8].isAvailable)    // September
    }

    func testSpentAndLeakShareCountOnlySortedPurchases() {
        let sept = TestSupport.date(2026, 9, 10, calendar: calendar)
        let unsorted = Transaction(amount: 999, date: sept, merchant: "Shop", source: .applePay)
        let data = [
            TestSupport.confirmed(75, verdict: .worthIt, date: sept),
            TestSupport.confirmed(25, verdict: .leak, date: sept),
            unsorted,
        ]
        let cell = MonthGrid.years(data, available: [month(2026, 9)], calendar: calendar)[0].cells[8]
        XCTAssertEqual(cell.spent, 100, accuracy: 0.001)
        XCTAssertEqual(cell.leakShare, 0.25, accuracy: 0.001)
    }

    func testEmptyMonthHasNoLeakShare() {
        let cell = MonthGrid.years([], available: [month(2026, 9)], calendar: calendar)[0].cells[8]
        XCTAssertEqual(cell.leakShare, 0)
    }
}
