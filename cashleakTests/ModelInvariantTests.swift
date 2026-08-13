import XCTest
import SwiftData
@testable import cashleak

/// The two invariants that silently corrupt the dataset when broken, plus the
/// CloudKit schema rules that only fail at runtime on a real device.
@MainActor
final class ModelInvariantTests: XCTestCase {

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

    // MARK: Invariant — everything enters unconfirmed

    /// No automated capture path may write a confirmed transaction. Manual
    /// entry is the deliberate exception, and it passes `isConfirmed` in
    /// explicitly rather than relying on the default.
    func testTransactionsDefaultToUnconfirmed() {
        let captured = Transaction(amount: 12.50, source: .applePay)
        XCTAssertFalse(captured.isConfirmed)
        XCTAssertTrue(captured.needsSorting)
        XCTAssertFalse(captured.countsTowardTotals)
    }

    func testDefaultVerdictIsUnrated() {
        let captured = Transaction(amount: 12.50, source: .bankAlert)
        XCTAssertEqual(captured.verdict, .unrated)
    }

    // MARK: Invariant — confirmed and verdict stay independent

    /// Confirmed means "this is real". Verdict means "I'd take it back". If
    /// confirming ever implied a verdict, a parser's guess would start counting
    /// as the user's judgement.
    func testConfirmingDoesNotSetAVerdict() {
        let transaction = Transaction(amount: 40, source: .scan)
        transaction.isConfirmed = true

        XCTAssertEqual(transaction.verdict, .unrated)
        XCTAssertTrue(transaction.countsTowardTotals)
    }

    func testSettingAVerdictDoesNotConfirm() {
        let transaction = Transaction(amount: 40, source: .scan)
        transaction.verdict = .leak

        XCTAssertFalse(transaction.isConfirmed)
        XCTAssertFalse(transaction.countsTowardTotals)
    }

    // MARK: Superseded

    func testSupersededIsExcludedFromTotalsButStillExists() throws {
        let transaction = TestSupport.confirmed(30, verdict: .leak)
        context.insert(transaction)
        transaction.isSuperseded = true
        try context.save()

        XCTAssertFalse(transaction.countsTowardTotals)

        // Recoverable — a wrong merge must never destroy data.
        let all = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(all.count, 1)
    }

    // MARK: Normalized merchant

    /// A stale normalized value breaks dedup with no visible symptom, so the
    /// initialiser and the setter both have to maintain it.
    func testInitPopulatesNormalizedMerchant() {
        let transaction = Transaction(amount: 5, merchant: "SQ *BLUE BOTTLE #22")
        XCTAssertEqual(transaction.normalizedMerchant, "blue bottle")
    }

    func testSetMerchantKeepsNormalizedInStep() {
        let transaction = Transaction(amount: 5, merchant: "Old Name")
        transaction.setMerchant("LOBLAWS #1043 TORONTO ON")
        XCTAssertEqual(transaction.normalizedMerchant, "loblaws toronto")
    }

    // MARK: Enum raw storage

    /// Enums are persisted as strings so that reordering cases can't remap
    /// existing records. An unknown value must degrade, not crash.
    func testUnknownRawValuesFallBackSafely() {
        let transaction = Transaction(amount: 1)
        transaction.sourceRaw = "somethingFromAFutureVersion"
        transaction.verdictRaw = "alsoUnknown"

        XCTAssertEqual(transaction.source, .manual)
        XCTAssertEqual(transaction.verdict, .unrated)
    }

    // MARK: Relationships

    func testCategoryInverseResolvesBothDirections() throws {
        let category = cashleak.Category(name: "Coffee")
        let transaction = TestSupport.confirmed(4.50, verdict: .worthIt, category: category)

        context.insert(category)
        context.insert(transaction)
        try context.save()

        XCTAssertEqual(transaction.category?.name, "Coffee")
        XCTAssertEqual(category.transactions?.count, 1)
    }

    func testDeletingCategoryLeavesTransactionIntact() throws {
        let category = cashleak.Category(name: "Coffee")
        let transaction = TestSupport.confirmed(4.50, verdict: .leak, category: category)
        context.insert(category)
        context.insert(transaction)
        try context.save()

        context.delete(category)
        try context.save()

        // The amount must survive — losing spend history because a category was
        // tidied up would be a serious data-loss bug.
        let all = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.amount, 4.50)
    }

    // MARK: Seeding

    func testCategoriesSeedExactlyOnce() throws {
        SeedData.seedCategoriesIfNeeded(in: context)
        let first = try context.fetchCount(FetchDescriptor<cashleak.Category>())

        SeedData.seedCategoriesIfNeeded(in: context)
        let second = try context.fetchCount(FetchDescriptor<cashleak.Category>())

        XCTAssertEqual(first, SeedData.defaultCategories.count)
        XCTAssertEqual(first, second)
    }

    // MARK: Trip

    func testTripEstimateUsesPersonalisedFormula() {
        let trip = Trip(
            name: "Lisbon",
            destination: "Lisbon",
            startDate: TestSupport.date(2026, 10, 1),
            endDate: TestSupport.date(2026, 10, 11),
            fixedCosts: 900,
            costMultiplier: 0.8,
            dailyDiscretionaryAtEstimate: 34
        )

        // 34 × 0.8 × 10 + 900
        XCTAssertEqual(trip.estimatedBudget, 1172, accuracy: 0.01)
    }

    func testTripDayCountIsNeverZero() {
        let sameDay = TestSupport.date(2026, 10, 1)
        let trip = Trip(name: "Day trip", startDate: sameDay, endDate: sameDay)
        XCTAssertEqual(trip.dayCount, 1)
    }
}
