import XCTest
@testable import cashleak

/// The "up to date / updated … ago" wording under the month (D-037).
@MainActor
final class SyncFreshnessTests: XCTestCase {

    private let calendar = TestSupport.torontoCalendar
    private lazy var now = TestSupport.date(2026, 10, 6, hour: 15, calendar: calendar)

    private func ago(_ seconds: TimeInterval) -> String {
        SyncFreshness.agoText(since: now.addingTimeInterval(-seconds), now: now, calendar: calendar)
    }

    func testUpToDateOnlyForTheFirstTenSeconds() {
        XCTAssertEqual(SyncFreshness.state(lastSync: now.addingTimeInterval(-3), isOffline: false, now: now, calendar: calendar), .upToDate)
        XCTAssertEqual(SyncFreshness.state(lastSync: now.addingTimeInterval(-10), isOffline: false, now: now, calendar: calendar), .ago("updated 10 sec ago"))
    }

    func testSecondsStepsAtTenAndThirty() {
        XCTAssertEqual(ago(12), "updated 10 sec ago")
        XCTAssertEqual(ago(29), "updated 10 sec ago")
        XCTAssertEqual(ago(30), "updated 30 sec ago")
        XCTAssertEqual(ago(59), "updated 30 sec ago")
    }

    func testEachMinuteUpToNine() {
        XCTAssertEqual(ago(60), "updated 1 min ago")
        XCTAssertEqual(ago(9 * 60 + 59), "updated 9 min ago")
    }

    func testMinuteStepsAfterTen() {
        XCTAssertEqual(ago(10 * 60), "updated 10 min ago")
        XCTAssertEqual(ago(14 * 60), "updated 10 min ago")
        XCTAssertEqual(ago(17 * 60), "updated 15 min ago")
        XCTAssertEqual(ago(25 * 60), "updated 20 min ago")
        XCTAssertEqual(ago(44 * 60), "updated 30 min ago")
        XCTAssertEqual(ago(59 * 60), "updated 45 min ago")
    }

    func testClockTimeAfterAnHour() {
        let when = now.addingTimeInterval(-2 * 3600)
        let time = when.formatted(date: .omitted, time: .shortened)
        XCTAssertEqual(ago(2 * 3600), "updated at \(time)")
    }

    func testYesterday() {
        let when = TestSupport.date(2026, 10, 5, hour: 21, minute: 10, calendar: calendar)
        let text = SyncFreshness.agoText(since: when, now: now, calendar: calendar)
        XCTAssertTrue(text.hasPrefix("updated yesterday, "), text)
    }

    func testNothingKnownSaysNothing() {
        XCTAssertNil(SyncFreshness.state(lastSync: nil, isOffline: false, now: now, calendar: calendar))
    }

    func testOfflineNeverClaimsUpToDate() {
        XCTAssertEqual(
            SyncFreshness.state(lastSync: now.addingTimeInterval(-2), isOffline: true, now: now, calendar: calendar),
            .offline("offline · updated just now")
        )
        XCTAssertEqual(
            SyncFreshness.state(lastSync: nil, isOffline: true, now: now, calendar: calendar),
            .offline("offline · showing what's on this phone")
        )
    }
}
