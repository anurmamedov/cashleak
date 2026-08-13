import XCTest
import SwiftData
@testable import cashleak

/// Posting runs on launch, on foreground, and from background refresh — three
/// triggers that can fire seconds apart. Double-posting rent is the kind of bug
/// a user notices immediately and never forgives.
@MainActor
final class RecurringPosterTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private let calendar = TestSupport.torontoCalendar

    override func setUp() async throws {
        container = try TestSupport.makeContainer()
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    private func transactions() throws -> [Transaction] {
        try context.fetch(FetchDescriptor<Transaction>()).filter { !$0.isSuperseded }
    }

    // MARK: Idempotence

    /// The property that matters most. Launch and foreground both call this.
    func testPostingTwiceDoesNotDouble() throws {
        let rule = RecurringRule(
            merchant: "Rent", amount: 2100, cadence: .monthly,
            nextRunDate: TestSupport.date(2026, 8, 1)
        )
        context.insert(rule)

        let now = TestSupport.date(2026, 8, 10)
        let first = RecurringPoster.postDue(asOf: now, calendar: calendar, in: context)
        let second = RecurringPoster.postDue(asOf: now, calendar: calendar, in: context)

        XCTAssertEqual(first.posted, 1)
        XCTAssertEqual(second.total, 0)
        XCTAssertEqual(try transactions().count, 1)
    }

    func testNextRunDateAdvancesPastNow() throws {
        let rule = RecurringRule(
            merchant: "Spotify", amount: 11.99, cadence: .monthly,
            nextRunDate: TestSupport.date(2026, 8, 1)
        )
        context.insert(rule)

        let now = TestSupport.date(2026, 8, 10)
        RecurringPoster.postDue(asOf: now, calendar: calendar, in: context)

        XCTAssertGreaterThan(rule.nextRunDate, now)
        XCTAssertEqual(rule.lastPostedDate, TestSupport.date(2026, 8, 1))
    }

    // MARK: Backfill

    /// Three months dormant owes three postings — not one, and not ninety.
    func testBackfillsOnePerMissedPeriod() throws {
        let rule = RecurringRule(
            merchant: "Insurance", amount: 88, cadence: .monthly,
            nextRunDate: TestSupport.date(2026, 5, 15)
        )
        context.insert(rule)

        let outcome = RecurringPoster.postDue(
            asOf: TestSupport.date(2026, 8, 16), calendar: calendar, in: context
        )

        XCTAssertEqual(outcome.posted, 4)
        XCTAssertEqual(try transactions().count, 4)
    }

    /// Backfilled charges land on their real dates, not all today — otherwise
    /// three months of rent would appear in one month's total.
    func testBackfilledTransactionsKeepTheirOwnDates() throws {
        let rule = RecurringRule(
            merchant: "Rent", amount: 2100, cadence: .monthly,
            nextRunDate: TestSupport.date(2026, 6, 1)
        )
        context.insert(rule)

        RecurringPoster.postDue(
            asOf: TestSupport.date(2026, 8, 10), calendar: calendar, in: context
        )

        let months = Set(try transactions().map { calendar.component(.month, from: $0.date) })
        XCTAssertEqual(months, [6, 7, 8])
    }

    // MARK: The entry invariant

    /// A rule is a prediction. The amount may have changed, the charge may not
    /// have landed. Only the user turns it into a fact.
    func testPostedTransactionsAreUnconfirmed() throws {
        let rule = RecurringRule(
            merchant: "Hydro", amount: 95, cadence: .monthly,
            nextRunDate: TestSupport.date(2026, 8, 1)
        )
        context.insert(rule)

        RecurringPoster.postDue(asOf: TestSupport.date(2026, 8, 10), calendar: calendar, in: context)

        let posted = try XCTUnwrap(try transactions().first)
        XCTAssertFalse(posted.isConfirmed)
        XCTAssertEqual(posted.verdict, .unrated)
        XCTAssertEqual(posted.source, .recurring)
    }

    /// Recurring is the one source where the category is known in advance — the
    /// user picked it when creating the rule.
    func testCategoryCarriesFromTheRule() throws {
        let category = cashleak.Category(name: "Utilities")
        context.insert(category)

        let rule = RecurringRule(
            merchant: "Hydro", amount: 95, cadence: .monthly,
            nextRunDate: TestSupport.date(2026, 8, 1), category: category
        )
        context.insert(rule)

        RecurringPoster.postDue(asOf: TestSupport.date(2026, 8, 10), calendar: calendar, in: context)

        XCTAssertEqual(try transactions().first?.category?.name, "Utilities")
    }

    // MARK: Enabled state

    func testPausedRulesDoNotPost() throws {
        let rule = RecurringRule(
            merchant: "Cancelled gym", amount: 60, cadence: .monthly,
            nextRunDate: TestSupport.date(2026, 1, 1), isEnabled: false
        )
        context.insert(rule)

        let outcome = RecurringPoster.postDue(
            asOf: TestSupport.date(2026, 8, 10), calendar: calendar, in: context
        )

        XCTAssertEqual(outcome.total, 0)
        XCTAssertTrue(try transactions().isEmpty)
    }

    func testFutureRulesDoNotPost() throws {
        let rule = RecurringRule(
            merchant: "Domain renewal", amount: 22, cadence: .yearly,
            nextRunDate: TestSupport.date(2027, 3, 1)
        )
        context.insert(rule)

        let outcome = RecurringPoster.postDue(
            asOf: TestSupport.date(2026, 8, 10), calendar: calendar, in: context
        )
        XCTAssertEqual(outcome.total, 0)
    }

    // MARK: Interaction with dedup

    /// A subscription billed to a card that also fires the Wallet trigger
    /// arrives twice. Dedup catches it, and the poster reports it honestly
    /// rather than counting it as posted.
    func testCollidesWithAnAlreadyCapturedCharge() throws {
        let chargeDate = TestSupport.date(2026, 8, 1)

        TransactionIngest.ingest(
            amount: 11.99, merchant: "Spotify",
            date: chargeDate, source: .applePay, into: context
        )

        let rule = RecurringRule(
            merchant: "Spotify", amount: 11.99, cadence: .monthly,
            nextRunDate: chargeDate
        )
        context.insert(rule)

        let outcome = RecurringPoster.postDue(
            asOf: TestSupport.date(2026, 8, 10), calendar: calendar, in: context
        )

        XCTAssertEqual(outcome.posted, 0)
        XCTAssertEqual(outcome.deduplicated, 1)
        XCTAssertEqual(try transactions().count, 1)
    }

    // MARK: Rejection

    /// A rule created from a template with no amount yet shouldn't post zeros.
    func testRulesWithNoAmountAreRejected() throws {
        let rule = RecurringRule(
            merchant: "Rent", amount: 0, cadence: .monthly,
            nextRunDate: TestSupport.date(2026, 8, 1)
        )
        context.insert(rule)

        let outcome = RecurringPoster.postDue(
            asOf: TestSupport.date(2026, 8, 10), calendar: calendar, in: context
        )

        XCTAssertEqual(outcome.posted, 0)
        XCTAssertEqual(outcome.rejected, 1)
        XCTAssertTrue(try transactions().isEmpty)
    }

    // MARK: Multiple rules

    func testAllDueRulesPostInOnePass() throws {
        for (merchant, amount) in [("Rent", 2100.0), ("Hydro", 95.0), ("Phone", 55.0)] {
            context.insert(RecurringRule(
                merchant: merchant, amount: amount, cadence: .monthly,
                nextRunDate: TestSupport.date(2026, 8, 1)
            ))
        }

        let outcome = RecurringPoster.postDue(
            asOf: TestSupport.date(2026, 8, 10), calendar: calendar, in: context
        )

        XCTAssertEqual(outcome.posted, 3)
    }
}
