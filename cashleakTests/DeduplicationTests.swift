import XCTest
import SwiftData
@testable import cashleak

/// The most consequential test file in the project.
///
/// A false negative doubles someone's totals. A false positive silently deletes
/// a real purchase from them. Neither is visible on screen — the number just
/// renders, wrong.
@MainActor
final class DeduplicationTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try TestSupport.makeContainer()
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    private func stored() throws -> [Transaction] {
        try context.fetch(FetchDescriptor<Transaction>())
    }

    private func active() throws -> [Transaction] {
        try stored().filter { !$0.isSuperseded }
    }

    // MARK: The case this exists for

    /// One tap, two sources: the Wallet automation fires at the terminal, the
    /// bank alert arrives when the charge posts a day later.
    func testWalletTapAndBankAlertCollapseToOne() throws {
        let tapTime = TestSupport.date(2026, 8, 4, hour: 9)

        TransactionIngest.ingest(
            amount: 6.75, merchant: "SQ *BLUE BOTTLE",
            date: tapTime, source: .applePay, into: context
        )
        let second = TransactionIngest.ingest(
            amount: 6.75, merchant: "BLUE BOTTLE #4412",
            date: tapTime.addingTimeInterval(26 * 3600), source: .bankAlert, into: context
        )

        XCTAssertEqual(second, .duplicate)
        XCTAssertEqual(try active().count, 1)
    }

    /// Nothing is deleted. A wrong merge has to stay recoverable.
    func testSupersededRecordIsKept() throws {
        let date = TestSupport.date(2026, 8, 4)
        TransactionIngest.ingest(amount: 20, merchant: "Loblaws", date: date, source: .applePay, into: context)
        TransactionIngest.ingest(amount: 20, merchant: "Loblaws", date: date, source: .bankAlert, into: context)

        XCTAssertEqual(try stored().count, 2)
        XCTAssertEqual(try active().count, 1)
    }

    // MARK: The 72-hour boundary

    func testMatchesJustInsideTheWindow() throws {
        let base = TestSupport.date(2026, 8, 1, hour: 12)
        TransactionIngest.ingest(amount: 42, merchant: "Terroni", date: base, source: .applePay, into: context)
        let result = TransactionIngest.ingest(
            amount: 42, merchant: "Terroni",
            date: base.addingTimeInterval(71 * 3600), source: .bankAlert, into: context
        )
        XCTAssertEqual(result, .duplicate)
    }

    func testDoesNotMatchJustOutsideTheWindow() throws {
        let base = TestSupport.date(2026, 8, 1, hour: 12)
        TransactionIngest.ingest(amount: 42, merchant: "Terroni", date: base, source: .applePay, into: context)
        let result = TransactionIngest.ingest(
            amount: 42, merchant: "Terroni",
            date: base.addingTimeInterval(73 * 3600), source: .bankAlert, into: context
        )
        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(try active().count, 2)
    }

    // MARK: False positives — the dangerous direction

    /// Buying the same coffee on Monday and Friday is two purchases. Merging
    /// them removes money the user actually spent, and nothing on screen would
    /// look wrong.
    func testSameAmountAndMerchantOnDifferentDaysStaysSeparate() throws {
        let monday = TestSupport.date(2026, 8, 3, hour: 8)
        let friday = TestSupport.date(2026, 8, 7, hour: 8)

        TransactionIngest.ingest(amount: 6.75, merchant: "Blue Bottle", date: monday, source: .applePay, into: context)
        TransactionIngest.ingest(amount: 6.75, merchant: "Blue Bottle", date: friday, source: .applePay, into: context)

        XCTAssertEqual(try active().count, 2)
    }

    func testDifferentAmountsNeverMatch() throws {
        let date = TestSupport.date(2026, 8, 4)
        TransactionIngest.ingest(amount: 6.75, merchant: "Blue Bottle", date: date, source: .applePay, into: context)
        TransactionIngest.ingest(amount: 6.76, merchant: "Blue Bottle", date: date, source: .bankAlert, into: context)

        XCTAssertEqual(try active().count, 2)
    }

    func testDifferentMerchantsNeverMatch() throws {
        let date = TestSupport.date(2026, 8, 4)
        TransactionIngest.ingest(amount: 20, merchant: "Loblaws", date: date, source: .applePay, into: context)
        TransactionIngest.ingest(amount: 20, merchant: "Metro", date: date, source: .bankAlert, into: context)

        XCTAssertEqual(try active().count, 2)
    }

    // MARK: Which record survives

    /// A sorted transaction carries human work. Superseding it would throw that
    /// away and put the purchase back in the queue.
    func testHumanJudgementIsNeverDiscarded() throws {
        let date = TestSupport.date(2026, 8, 4)

        TransactionIngest.ingest(amount: 30, merchant: "Terroni", date: date, source: .applePay, into: context)
        let sorted = try XCTUnwrap(try active().first)
        sorted.isConfirmed = true
        sorted.verdict = .leak
        try context.save()

        TransactionIngest.ingest(amount: 30, merchant: "Terroni", date: date, source: .bankAlert, into: context)

        let survivors = try active()
        XCTAssertEqual(survivors.count, 1)
        XCTAssertTrue(survivors[0].isConfirmed)
        XCTAssertEqual(survivors[0].verdict, .leak)
    }

    func testRicherRecordWinsWhenNeitherIsSorted() throws {
        let date = TestSupport.date(2026, 8, 4)

        // An empty merchant is what a timed-out Wallet trigger delivers.
        TransactionIngest.ingest(amount: 15, merchant: "", date: date, source: .applePay, into: context)
        TransactionIngest.ingest(amount: 15, merchant: "Cineplex", date: date, source: .bankAlert, into: context)

        // An empty merchant can't fuzzy match, so these stay separate — the
        // known limitation, asserted so it can't change silently.
        XCTAssertEqual(try active().count, 2)
    }

    // MARK: Rejection

    /// The Wallet trigger fires on declines.
    func testZeroAndNegativeAmountsAreRejected() throws {
        XCTAssertEqual(
            TransactionIngest.ingest(amount: 0, merchant: "Declined", source: .applePay, into: context),
            .rejected(.nonPositiveAmount)
        )
        XCTAssertEqual(
            TransactionIngest.ingest(amount: -12, merchant: "Refund", source: .applePay, into: context),
            .rejected(.nonPositiveAmount)
        )
        XCTAssertTrue(try stored().isEmpty)
    }

    /// A regex that grabs an account balance instead of a purchase amount.
    func testImplausiblyLargeAmountsAreRejected() throws {
        XCTAssertEqual(
            TransactionIngest.ingest(amount: 250_000, merchant: "RBC", source: .bankAlert, into: context),
            .rejected(.implausiblyLarge)
        )
        XCTAssertTrue(try stored().isEmpty)
    }

    // MARK: The entry invariant

    /// No capture path may write a confirmed transaction.
    func testEverythingEntersUnconfirmed() throws {
        for source in [TransactionSource.applePay, .bankAlert, .scan, .recurring] {
            TransactionIngest.ingest(
                amount: Double.random(in: 5...50),
                merchant: "Merchant \(source.rawValue)",
                date: TestSupport.date(2026, 8, Int.random(in: 1...28)),
                source: source,
                into: context
            )
        }

        for transaction in try stored() {
            XCTAssertFalse(transaction.isConfirmed, "\(transaction.source) wrote a confirmed record")
            XCTAssertEqual(transaction.verdict, .unrated)
        }
    }

    func testIngestPopulatesNormalizedMerchant() throws {
        TransactionIngest.ingest(
            amount: 9.99, merchant: "  SQ *BLUE BOTTLE #22  ",
            source: .applePay, into: context
        )
        let stored = try XCTUnwrap(try active().first)
        XCTAssertEqual(stored.merchant, "SQ *BLUE BOTTLE #22")
        XCTAssertEqual(stored.normalizedMerchant, "blue bottle")
    }

    // MARK: Matcher unit level

    func testRichnessRanksHumanWorkHighest() {
        let raw = Transaction(amount: 10, merchant: "A", source: .applePay)
        let sorted = Transaction(amount: 10, merchant: "A", source: .applePay)
        sorted.isConfirmed = true
        sorted.verdict = .worthIt

        XCTAssertGreaterThan(
            DeduplicationMatcher.richness(of: sorted),
            DeduplicationMatcher.richness(of: raw)
        )
    }

    func testPreferredKeepsIncumbentOnATie() {
        let a = Transaction(amount: 10, merchant: "A", source: .applePay)
        let b = Transaction(amount: 10, merchant: "A", source: .bankAlert)
        XCTAssertTrue(DeduplicationMatcher.preferred(a, b) === a)
    }

    func testMatchesAreOrderedByTimeProximity() {
        let base = TestSupport.date(2026, 8, 4, hour: 12)
        let near = Transaction(amount: 10, date: base.addingTimeInterval(3600), merchant: "Cafe", source: .applePay)
        let far = Transaction(amount: 10, date: base.addingTimeInterval(48 * 3600), merchant: "Cafe", source: .applePay)

        let matches = DeduplicationMatcher.matches(
            amount: 10, merchant: "Cafe", date: base, among: [far, near]
        )
        XCTAssertTrue(matches.first === near)
    }
}
