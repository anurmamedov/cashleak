import XCTest
@testable import cashleak

/// Parsing the amount the Wallet trigger actually sends.
///
/// The intent originally declared `amount` as `Double`. Shortcuts hands the
/// value over as text — `$7.29` — and refuses to coerce it, so every capture
/// failed with "couldn't convert from Text to Number" while the automation,
/// the trigger and the intent all looked correct. These tests exist so that
/// never silently returns.
final class AmountParsingTests: XCTestCase {

    private func parse(_ s: String) -> Double {
        LogWalletTransaction.parseAmount(s)
    }

    // MARK: What the device actually sent

    func testCurrencySymbolIsStripped() {
        XCTAssertEqual(parse("$7.29"), 7.29, accuracy: 0.001)
    }

    func testPlainNumberStillWorks() {
        XCTAssertEqual(parse("7.29"), 7.29, accuracy: 0.001)
    }

    func testCanadianAndUsPrefixes() {
        XCTAssertEqual(parse("CA$83.26"), 83.26, accuracy: 0.001)
        XCTAssertEqual(parse("US$14.68"), 14.68, accuracy: 0.001)
    }

    func testWhitespaceAndNonBreakingSpace() {
        XCTAssertEqual(parse("  $146.73 "), 146.73, accuracy: 0.001)
        XCTAssertEqual(parse("\u{00A0}$54.14"), 54.14, accuracy: 0.001)
    }

    // MARK: Separators

    func testThousandsSeparatorWithDotDecimal() {
        XCTAssertEqual(parse("$1,234.56"), 1234.56, accuracy: 0.001)
    }

    func testEuropeanCommaDecimal() {
        XCTAssertEqual(parse("7,29"), 7.29, accuracy: 0.001)
        XCTAssertEqual(parse("1.234,56"), 1234.56, accuracy: 0.001)
    }

    /// A lone comma with three trailing digits is thousands, not cents.
    func testCommaAsThousandsWithNoDecimal() {
        XCTAssertEqual(parse("1,234"), 1234, accuracy: 0.001)
    }

    // MARK: Rejection

    /// Returns 0 rather than guessing. `TransactionIngest` then rejects it as
    /// a non-positive amount instead of storing a fabricated number.
    func testNonNumericReturnsZero() {
        XCTAssertEqual(parse(""), 0, accuracy: 0.001)
        XCTAssertEqual(parse("Device Details"), 0, accuracy: 0.001)
        XCTAssertEqual(parse("$"), 0, accuracy: 0.001)
    }

    func testRefundKeepsItsSign() {
        XCTAssertEqual(parse("-$7.29"), -7.29, accuracy: 0.001)
    }
}
