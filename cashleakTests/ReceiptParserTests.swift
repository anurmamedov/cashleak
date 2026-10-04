import XCTest
@testable import cashleak

/// Receipt reading, minus the camera (D-036).
///
/// Vision's output is simulated as positioned lines, the way it arrives: a
/// label at the left edge and its figure at the right edge are two separate
/// observations at the same height. These are written from the layouts of
/// common Canadian receipts, not from real scans — swap in real Vision output
/// once there are photos to take it from.
final class ReceiptParserTests: XCTestCase {

    private let calendar = TestSupport.torontoCalendar
    private lazy var now = TestSupport.date(2026, 10, 4, hour: 15, calendar: calendar)

    /// Builds lines top to bottom. The first row is printed larger, as store
    /// names usually are.
    private func receipt(_ rows: [(String, String?)], headerScale: Double = 2) -> [ReceiptLine] {
        // Rows sit about one and a half line-heights apart, as printed.
        let step = 0.03
        var lines: [ReceiptLine] = []
        for (index, row) in rows.enumerated() {
            let height = index == 0 ? 0.02 * headerScale : 0.02
            let midY = 0.95 - Double(index) * step
            lines.append(ReceiptLine(row.0, box: CGRect(x: 0.1, y: midY - height / 2, width: 0.4, height: height)))
            if let right = row.1 {
                lines.append(ReceiptLine(right, box: CGRect(x: 0.7, y: midY - 0.01, width: 0.2, height: 0.02)))
            }
        }
        return lines
    }

    private func parse(_ lines: [ReceiptLine]) -> ReceiptReading {
        ReceiptParser.parse(lines, now: now, calendar: calendar)
    }

    private func day(_ date: Date?) -> DateComponents? {
        date.map { calendar.dateComponents([.year, .month, .day], from: $0) }
    }

    // MARK: Whole receipts

    func testGroceryReceipt() {
        let reading = parse(receipt([
            ("LOBLAWS #1029", nil),
            ("60 CARL HALL RD TORONTO ON", nil),
            ("TEL 416-555-0172", nil),
            ("10/03/26 18:42", nil),
            ("BANANAS", "1.84"),
            ("MILK 2L", "5.49"),
            ("CHICKEN 1.2 KG", "18.62"),
            ("SUBTOTAL", "45.10"),
            ("HST 13%", "3.17"),
            ("TOTAL", "48.27"),
            ("VISA **** 4411", "48.27"),
            ("TOTAL SAVINGS", "2.50"),
        ]))

        XCTAssertEqual(reading.merchant?.value, "Loblaws")
        XCTAssertEqual(reading.total?.value, 48.27)
        XCTAssertEqual(reading.total?.confidence, .sure)
        XCTAssertEqual(day(reading.date?.value), DateComponents(year: 2026, month: 10, day: 3))
        // 10/03 could be 3 October or 10 March — a guess, so it's marked.
        XCTAssertEqual(reading.date?.confidence, .check)
        XCTAssertEqual(reading.categoryHint, "Groceries")
    }

    func testRestaurantWithTypedTipTakesTheFinalTotal() {
        let reading = parse(receipt([
            ("TERRONI", nil),
            ("Server: Marco   Table 12", nil),
            ("Oct 2, 2026  20:15", nil),
            ("Margherita", "21.00"),
            ("Subtotal", "45.00"),
            ("HST", "5.85"),
            ("Total", "50.85"),
            ("Tip", "7.63"),
            ("Total", "58.48"),
            ("Mastercard", "58.48"),
        ]))

        XCTAssertEqual(reading.total?.value, 58.48)
        XCTAssertEqual(reading.total?.confidence, .sure, "Matches the card line")
        XCTAssertEqual(reading.merchant?.value, "Terroni")
        XCTAssertEqual(day(reading.date?.value), DateComponents(year: 2026, month: 10, day: 2))
        XCTAssertEqual(reading.date?.confidence, .sure)
        XCTAssertEqual(reading.categoryHint, "Dining out")
    }

    func testGasStation() {
        let reading = parse(receipt([
            ("PETRO-CANADA", nil),
            ("2026-09-30 07:55", nil),
            ("PUMP 4  REGULAR", nil),
            ("42.310 LITRES @ 1.459", nil),
            ("FUEL TOTAL", "61.73"),
            ("DEBIT", "61.73"),
        ]))

        XCTAssertEqual(reading.total?.value, 61.73)
        XCTAssertEqual(day(reading.date?.value), DateComponents(year: 2026, month: 9, day: 30))
        XCTAssertEqual(reading.date?.confidence, .sure)
        XCTAssertEqual(reading.categoryHint, "Fuel")
        XCTAssertEqual(reading.merchant?.value.lowercased(), "petro-canada")
    }

    func testFrenchReceipt() {
        let reading = parse(receipt([
            ("METRO", nil),
            ("03 OCT 2026", nil),
            ("SOUS-TOTAL", "20,00"),
            ("TPS", "1,00"),
            ("TVQ", "2,00"),
            ("TOTAL", "23,00"),
        ]))

        XCTAssertEqual(reading.total?.value, 23.00)
        XCTAssertEqual(day(reading.date?.value), DateComponents(year: 2026, month: 10, day: 3))
        XCTAssertEqual(reading.merchant?.value, "Metro")
    }

    // MARK: Total

    func testSubtotalAndTaxAreNeverTheTotal() {
        let reading = parse(receipt([
            ("SHOP", nil),
            ("SUBTOTAL", "100.00"),
            ("TAX", "13.00"),
        ]))
        // No TOTAL row — falls back to the largest figure, and says so.
        XCTAssertEqual(reading.total?.value, 100.00)
        XCTAssertEqual(reading.total?.confidence, .check)
    }

    func testAmountPrintedOnTheLineUnderTotal() {
        let reading = parse(receipt([
            ("SHOP", nil),
            ("TOTAL", nil),
            ("$12.40", nil),
        ]))
        XCTAssertEqual(reading.total?.value, 12.40)
    }

    func testTaxInclusiveTotalStillCounts() {
        let reading = parse(receipt([
            ("CAFE", nil),
            ("TOTAL (TAX INCL.)", "6.10"),
        ]))
        XCTAssertEqual(reading.total?.value, 6.10)
    }

    func testAmountsIgnoreDiscountsPercentagesAndDates() {
        XCTAssertEqual(ReceiptParser.amounts(in: "COUPON  -2.00"), [])
        XCTAssertEqual(ReceiptParser.amounts(in: "HST 13%  3.17"), [3.17])
        XCTAssertEqual(ReceiptParser.amounts(in: "10.03.26"), [])
        XCTAssertEqual(ReceiptParser.amounts(in: "TOTAL $1,284.00"), [1284.00])
        XCTAssertEqual(ReceiptParser.amounts(in: "TOTAL 23,00"), [23.00])
    }

    // MARK: Date

    func testFutureDateIsRejected() {
        let reading = parse(receipt([("SHOP", nil), ("12/25/26", nil), ("TOTAL", "5.00")]))
        XCTAssertNil(reading.date)
    }

    func testDayFirstWhenUnambiguous() {
        let reading = parse(receipt([("SHOP", nil), ("28/09/2026", nil), ("TOTAL", "5.00")]))
        XCTAssertEqual(day(reading.date?.value), DateComponents(year: 2026, month: 9, day: 28))
        XCTAssertEqual(reading.date?.confidence, .sure)
    }

    func testOldReceiptIsMarkedForChecking() {
        let reading = parse(receipt([("SHOP", nil), ("2026-03-15", nil), ("TOTAL", "5.00")]))
        XCTAssertEqual(day(reading.date?.value), DateComponents(year: 2026, month: 3, day: 15))
        XCTAssertEqual(reading.date?.confidence, .check)
    }

    func testImpossibleDateIsIgnored() {
        let reading = parse(receipt([("SHOP", nil), ("2026-02-31", nil), ("TOTAL", "5.00")]))
        XCTAssertNil(reading.date)
    }

    // MARK: Merchant

    func testMerchantSkipsWelcomeLinesAndAddresses() {
        let reading = parse(receipt([
            ("WELCOME TO", nil),
            ("1029 QUEEN ST W", nil),
            ("NO FRILLS", nil),
            ("TOTAL", "9.99"),
        ], headerScale: 1))
        XCTAssertEqual(reading.merchant?.value, "No Frills")
    }

    func testCleanMerchant() {
        XCTAssertEqual(ReceiptParser.cleanMerchant("TIM HORTONS #4412"), "Tim Hortons")
        XCTAssertEqual(ReceiptParser.cleanMerchant("Starbucks Coffee"), "Starbucks Coffee")
        XCTAssertEqual(ReceiptParser.cleanMerchant("SHOPPERS DRUG MART 1234"), "Shoppers Drug Mart")
    }

    // MARK: Nothing usable

    func testBlankPhotoReadsAsEmpty() {
        XCTAssertTrue(parse([]).isEmpty)
        XCTAssertTrue(parse(receipt([("~~", nil)])).isEmpty)
    }

    func testRowsJoinLabelAndFigure() {
        let rows = ReceiptParser.rows(from: receipt([("SHOP", nil), ("TOTAL", "4.19")]))
        XCTAssertEqual(rows.map(\.text), ["SHOP", "TOTAL  4.19"])
    }
}
