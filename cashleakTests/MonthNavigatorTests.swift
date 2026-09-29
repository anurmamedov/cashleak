import XCTest
@testable import cashleak

/// Overview's month switcher.
///
/// A switcher that skips a month, repeats one, or lets you arrow into the
/// future looks fine until someone notices July is missing. These pin the
/// edges down.
final class MonthNavigatorTests: XCTestCase {

    private let calendar = TestSupport.torontoCalendar

    private func month(_ year: Int, _ month: Int) -> Date {
        TestSupport.date(year, month, 1, hour: 0, calendar: calendar)
    }

    private func isSameMonth(_ a: Date?, _ b: Date) -> Bool {
        guard let a else { return false }
        return calendar.isDate(a, equalTo: b, toGranularity: .month)
    }

    // MARK: Available months

    /// A new user with no history still has the current month to look at.
    func testNoHistoryGivesOnlyTheCurrentMonth() {
        let now = TestSupport.date(2026, 9, 28, calendar: calendar)
        let months = MonthNavigator.availableMonths(from: [], now: now, calendar: calendar)
        XCTAssertEqual(months.count, 1)
        XCTAssertTrue(isSameMonth(months.first, now))
    }

    /// Empty months in between are kept, so the arrows never jump.
    func testQuietMonthsInBetweenAreIncluded() {
        let now = TestSupport.date(2026, 9, 28, calendar: calendar)
        let dates = [TestSupport.date(2026, 6, 15, calendar: calendar)]
        let months = MonthNavigator.availableMonths(from: dates, now: now, calendar: calendar)

        XCTAssertEqual(months.count, 4) // June, July, August, September
        XCTAssertTrue(isSameMonth(months.first, month(2026, 6)))
        XCTAssertTrue(isSameMonth(months.last, month(2026, 9)))
    }

    /// A purchase at 23:59 on the last day belongs to that month, not the next.
    func testLastMinuteOfAMonthStaysInThatMonth() {
        let now = TestSupport.date(2026, 9, 28, calendar: calendar)
        let dates = [TestSupport.date(2026, 7, 31, hour: 23, minute: 59, calendar: calendar)]
        let months = MonthNavigator.availableMonths(from: dates, now: now, calendar: calendar)
        XCTAssertTrue(isSameMonth(months.first, month(2026, 7)))
    }

    /// A backdated or mis-dated future transaction can't create future months
    /// to arrow into.
    func testFutureDatesNeverExtendPastNow() {
        let now = TestSupport.date(2026, 9, 28, calendar: calendar)
        let dates = [TestSupport.date(2026, 12, 1, calendar: calendar)]
        let months = MonthNavigator.availableMonths(from: dates, now: now, calendar: calendar)
        XCTAssertEqual(months.count, 1)
        XCTAssertTrue(isSameMonth(months.last, now))
    }

    // MARK: Moving

    func testJanuaryGoesBackToThePreviousDecember() {
        let now = TestSupport.date(2027, 1, 10, calendar: calendar)
        let dates = [TestSupport.date(2026, 11, 5, calendar: calendar)]
        let months = MonthNavigator.availableMonths(from: dates, now: now, calendar: calendar)

        let previous = MonthNavigator.previous(before: month(2027, 1), in: months, calendar: calendar)
        XCTAssertTrue(isSameMonth(previous, month(2026, 12)))
    }

    func testCannotGoBeforeTheFirstMonth() {
        let now = TestSupport.date(2026, 9, 28, calendar: calendar)
        let months = MonthNavigator.availableMonths(
            from: [TestSupport.date(2026, 8, 3, calendar: calendar)], now: now, calendar: calendar
        )
        XCTAssertNil(MonthNavigator.previous(before: month(2026, 8), in: months, calendar: calendar))
    }

    func testCannotGoPastTheCurrentMonth() {
        let now = TestSupport.date(2026, 9, 28, calendar: calendar)
        let months = MonthNavigator.availableMonths(
            from: [TestSupport.date(2026, 8, 3, calendar: calendar)], now: now, calendar: calendar
        )
        XCTAssertNil(MonthNavigator.next(after: month(2026, 9), in: months, calendar: calendar))
        XCTAssertTrue(isSameMonth(
            MonthNavigator.next(after: month(2026, 8), in: months, calendar: calendar),
            month(2026, 9)
        ))
    }

    /// The selected month may be any instant inside it, not just the 1st.
    func testMovingWorksFromMidMonth() {
        let now = TestSupport.date(2026, 9, 28, calendar: calendar)
        let months = MonthNavigator.availableMonths(
            from: [TestSupport.date(2026, 7, 3, calendar: calendar)], now: now, calendar: calendar
        )
        let midAugust = TestSupport.date(2026, 8, 17, hour: 15, calendar: calendar)
        XCTAssertTrue(isSameMonth(
            MonthNavigator.previous(before: midAugust, in: months, calendar: calendar),
            month(2026, 7)
        ))
    }

    func testLastDayOfFebruaryInALeapYear() {
        let last = MonthNavigator.lastDay(of: month(2028, 2), calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: last), 29)
    }

    // MARK: Per day

    /// A finished month averages over all of its days.
    func testPerDayForAFinishedMonthUsesTheWholeMonth() {
        let august = TestSupport.date(2025, 8, 10, calendar: calendar)
        let transactions = [TestSupport.confirmed(310, verdict: .worthIt, date: august)]
        let summary = SpendingSummary.make(from: transactions, month: august, calendar: calendar)

        XCTAssertEqual(summary.daysElapsed, 31)
        XCTAssertEqual(summary.perDay, 10, accuracy: 0.001)
    }

    func testPerDayIsZeroWithNothingSpent() {
        XCTAssertEqual(SpendingSummary.empty.perDay, 0)
    }
}
