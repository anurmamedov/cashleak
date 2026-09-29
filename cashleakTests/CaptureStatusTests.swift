import XCTest
@testable import cashleak

/// The status line on the setup screen and the Profile row.
///
/// Written after the first real device test, where ten manual runs of the
/// shortcut made a two-state check say "working" while not one capture had
/// come from a card tap. A green light that lies is worse than none.
final class CaptureStatusTests: XCTestCase {

    private func entry(_ merchant: String, secondsAgo: TimeInterval = 0) -> CaptureLogEntry {
        let entry = CaptureLogEntry(
            rawMerchant: merchant, amount: 4.19, source: .applePay, outcome: "inserted"
        )
        entry.receivedAt = .now.addingTimeInterval(-secondsAgo)
        return entry
    }

    func testEmptyLogIsNotConnected() {
        XCTAssertEqual(CaptureStatus.from([]), .notConnected)
    }

    /// Manual runs and unconnected Merchant fields both look like this.
    /// Neither is working.
    func testCapturesWithoutAMerchantAreNotWorking() {
        let captures = [entry(""), entry(""), entry("")]
        XCTAssertEqual(CaptureStatus.from(captures), .missingMerchant)
    }

    func testOneRealCaptureIsWorking() {
        let real = entry("Tim Hortons", secondsAgo: 60)
        guard case let .working(_, merchant) = CaptureStatus.from([entry(""), real]) else {
            return XCTFail("A capture with a merchant should read as working")
        }
        XCTAssertEqual(merchant, "Tim Hortons")
    }

    /// The log is sorted newest first, so the first real capture is the most
    /// recent one — a later test run without a merchant doesn't undo it.
    func testMostRecentRealCaptureIsReported() {
        let captures = [entry("", secondsAgo: 10), entry("Sobeys", secondsAgo: 100), entry("No Frills", secondsAgo: 1000)]
        guard case let .working(_, merchant) = CaptureStatus.from(captures) else {
            return XCTFail("Expected working")
        }
        XCTAssertEqual(merchant, "Sobeys")
    }
}
