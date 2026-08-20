import XCTest
@testable import cashleak

final class DailyReminderTests: XCTestCase {

    func testNoReminderWhenQueueIsEmpty() {
        XCTAssertNil(DailyReminder.plan(unsortedCount: 0, hour: 21, minute: 0))
    }

    func testSingularReminderCopy() throws {
        let plan = try XCTUnwrap(DailyReminder.plan(unsortedCount: 1, hour: 21, minute: 0))
        XCTAssertEqual(plan.title, "1 purchase is waiting")
    }

    func testPluralReminderCopy() throws {
        let plan = try XCTUnwrap(DailyReminder.plan(unsortedCount: 4, hour: 21, minute: 0))
        XCTAssertEqual(plan.title, "4 purchases are waiting")
        XCTAssertTrue(plan.body.contains("Worth it or leak?"))
    }

    func testReminderTimeIsClampedToAValidClockTime() throws {
        let plan = try XCTUnwrap(DailyReminder.plan(unsortedCount: 1, hour: 30, minute: -4))
        XCTAssertEqual(plan.hour, 23)
        XCTAssertEqual(plan.minute, 0)
        XCTAssertEqual(plan.dateComponents.hour, 23)
        XCTAssertEqual(plan.dateComponents.minute, 0)
    }

    func testNotificationRoutesToSort() {
        let destination = NotificationRoute.destination(for: [
            DailyReminder.routeKey: DailyReminder.sortRoute
        ])
        XCTAssertEqual(destination, .sort)
    }

    func testUnknownNotificationHasNoRoute() {
        XCTAssertNil(NotificationRoute.destination(for: [DailyReminder.routeKey: "overview"]))
        XCTAssertNil(NotificationRoute.destination(for: [:]))
    }

    func testNextRefreshIsTodayBeforeThreePM() {
        let calendar = TestSupport.torontoCalendar
        let now = TestSupport.date(2026, 8, 20, hour: 10)
        XCTAssertEqual(
            BackgroundRefresh.nextAfternoon(after: now, calendar: calendar),
            TestSupport.date(2026, 8, 20, hour: 15)
        )
    }

    func testNextRefreshIsTomorrowAfterThreePM() {
        let calendar = TestSupport.torontoCalendar
        let now = TestSupport.date(2026, 8, 20, hour: 18)
        XCTAssertEqual(
            BackgroundRefresh.nextAfternoon(after: now, calendar: calendar),
            TestSupport.date(2026, 8, 21, hour: 15)
        )
    }
}
