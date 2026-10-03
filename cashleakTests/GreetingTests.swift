import XCTest
@testable import cashleak

/// The hello on Overview: right for the hour, and never "Hi, ." (D-032).
@MainActor
final class GreetingTests: XCTestCase {

    func testMomentsByHour() {
        XCTAssertEqual(Greeting.Moment(hour: 5), .morning)
        XCTAssertEqual(Greeting.Moment(hour: 11), .morning)
        XCTAssertEqual(Greeting.Moment(hour: 12), .afternoon)
        XCTAssertEqual(Greeting.Moment(hour: 16), .afternoon)
        XCTAssertEqual(Greeting.Moment(hour: 17), .evening)
        XCTAssertEqual(Greeting.Moment(hour: 21), .evening)
        XCTAssertEqual(Greeting.Moment(hour: 22), .late)
        XCTAssertEqual(Greeting.Moment(hour: 0), .late)
        XCTAssertEqual(Greeting.Moment(hour: 4), .late)
    }

    func testWithName() {
        XCTAssertEqual(Greeting.text(for: .morning, firstName: "Anar"), "Morning, Anar")
        XCTAssertEqual(Greeting.text(for: .late, firstName: "Anar"), "Late one, Anar")
    }

    /// No name, no comma.
    func testWithoutName() {
        XCTAssertEqual(Greeting.text(for: .morning, firstName: ""), "Good morning")
        XCTAssertEqual(Greeting.text(for: .evening, firstName: "   "), "Good evening")
    }

    func testFollowsTheCalendarItIsGiven() {
        let calendar = TestSupport.torontoCalendar
        let nineAM = TestSupport.date(2026, 10, 3, hour: 9, calendar: calendar)
        XCTAssertEqual(Greeting.moment(at: nineAM, calendar: calendar), .morning)
    }
}
