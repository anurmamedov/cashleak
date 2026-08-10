import XCTest
@testable import cashleak

/// Date arithmetic fails quietly and only on specific days of the year, which
/// is exactly the profile of a bug that ships.
///
/// Every test pins the calendar to America/Toronto so results don't depend on
/// the machine's timezone.
final class RecurringRuleTests: XCTestCase {

    private let calendar = TestSupport.torontoCalendar

    // MARK: Month-end clamping

    /// Rent on the 31st must not roll into March. `Calendar` clamps to the last
    /// valid day, which is the behaviour we want.
    func testMonthlyOnThe31stClampsInShortMonths() {
        let jan31 = TestSupport.date(2026, 1, 31)
        let rule = RecurringRule(merchant: "Rent", amount: 2100, cadence: .monthly, nextRunDate: jan31)

        let feb = rule.dateAfter(jan31, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: feb), 2)
        XCTAssertEqual(calendar.component(.day, from: feb), 28)
    }

    func testMonthlyOnThe31stHandlesLeapFebruary() {
        let jan31 = TestSupport.date(2028, 1, 31)
        let rule = RecurringRule(merchant: "Rent", amount: 2100, cadence: .monthly, nextRunDate: jan31)

        let feb = rule.dateAfter(jan31, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: feb), 29)
    }

    func testMonthlyFrom30thAprilLandsOn30thMay() {
        let apr30 = TestSupport.date(2026, 4, 30)
        let rule = RecurringRule(merchant: "Gym", amount: 60, cadence: .monthly, nextRunDate: apr30)

        let may = rule.dateAfter(apr30, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: may), 5)
        XCTAssertEqual(calendar.component(.day, from: may), 30)
    }

    // MARK: DST

    /// Spring forward, 2026-03-08 in Toronto. A naive 7×86,400 seconds would
    /// land an hour off and could slip the posting into the previous day.
    func testWeeklyAcrossSpringForwardKeepsWallClockTime() {
        let before = TestSupport.date(2026, 3, 5, hour: 9)
        let rule = RecurringRule(merchant: "Cleaner", amount: 120, cadence: .weekly, nextRunDate: before)

        let after = rule.dateAfter(before, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: after), 12)
        XCTAssertEqual(calendar.component(.hour, from: after), 9)
    }

    /// Fall back, 2026-11-01 in Toronto.
    func testWeeklyAcrossFallBackKeepsWallClockTime() {
        let before = TestSupport.date(2026, 10, 29, hour: 9)
        let rule = RecurringRule(merchant: "Cleaner", amount: 120, cadence: .weekly, nextRunDate: before)

        let after = rule.dateAfter(before, calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: after), 5)
        XCTAssertEqual(calendar.component(.hour, from: after), 9)
    }

    // MARK: Backfill

    /// A rule dormant for three months owes three postings — not one, and not
    /// one per day since.
    func testBackfillsOnePostingPerMissedPeriod() {
        let start = TestSupport.date(2026, 1, 15)
        let now = TestSupport.date(2026, 4, 16)
        let rule = RecurringRule(merchant: "Insurance", amount: 88, cadence: .monthly, nextRunDate: start)

        let due = rule.datesDue(asOf: now, calendar: calendar)
        XCTAssertEqual(due.count, 4)
    }

    func testNothingDueBeforeTheFirstRunDate() {
        let future = TestSupport.date(2027, 1, 1)
        let now = TestSupport.date(2026, 8, 10)
        let rule = RecurringRule(merchant: "Domain", amount: 22, cadence: .yearly, nextRunDate: future)

        XCTAssertTrue(rule.datesDue(asOf: now, calendar: calendar).isEmpty)
    }

    func testDisabledRuleNeverPosts() {
        let past = TestSupport.date(2026, 1, 1)
        let now = TestSupport.date(2026, 8, 10)
        let rule = RecurringRule(
            merchant: "Cancelled gym",
            amount: 60,
            cadence: .monthly,
            nextRunDate: past,
            isEnabled: false
        )

        XCTAssertTrue(rule.datesDue(asOf: now, calendar: calendar).isEmpty)
    }

    /// A rule with a corrupt date must not spin forever.
    func testBackfillIsBounded() {
        let ancient = TestSupport.date(1970, 1, 1)
        let now = TestSupport.date(2026, 8, 10)
        let rule = RecurringRule(merchant: "Ancient", amount: 1, cadence: .weekly, nextRunDate: ancient)

        XCTAssertLessThanOrEqual(rule.datesDue(asOf: now, calendar: calendar).count, 512)
    }

    // MARK: Cadence

    func testBiweeklyIsFourteenDays() {
        let start = TestSupport.date(2026, 6, 1)
        let rule = RecurringRule(merchant: "Payroll", amount: 0, cadence: .biweekly, nextRunDate: start)
        let next = rule.dateAfter(start, calendar: calendar)
        XCTAssertEqual(calendar.dateComponents([.day], from: start, to: next).day, 14)
    }

    func testQuarterlyAdvancesThreeMonths() {
        let start = TestSupport.date(2026, 1, 10)
        let rule = RecurringRule(merchant: "Tax", amount: 0, cadence: .quarterly, nextRunDate: start)
        let next = rule.dateAfter(start, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: next), 4)
    }
}
