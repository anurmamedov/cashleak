import XCTest
import SwiftData
@testable import cashleak

/// Merchant memory is the closest the app comes to guessing on the user's
/// behalf. These tests pin down exactly how far that guess is allowed to go.
@MainActor
final class MerchantMemoryTests: XCTestCase {

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

    private func insert(
        merchant: String,
        category: Category?,
        date: Date,
        verdict: Verdict = .worthIt
    ) {
        let transaction = Transaction(
            amount: 10, date: date, merchant: merchant,
            source: .manual, verdict: verdict, isConfirmed: true, category: category
        )
        context.insert(transaction)
        try? context.save()
    }

    // MARK: Recall

    func testRecallsTheCategoryUsedForAMerchant() {
        let coffee = Category(name: "Coffee")
        context.insert(coffee)
        insert(merchant: "Blue Bottle", category: coffee, date: TestSupport.date(2026, 8, 1))

        let recalled = MerchantMemory.lastCategory(forMerchant: "Blue Bottle", in: context)
        XCTAssertEqual(recalled?.name, "Coffee")
    }

    /// Real feeds deliver the same shop three different ways. Memory has to
    /// match on the normalized form or it never fires.
    func testMatchesAcrossMerchantFormats() {
        let coffee = Category(name: "Coffee")
        context.insert(coffee)
        insert(merchant: "SQ *BLUE BOTTLE", category: coffee, date: TestSupport.date(2026, 8, 1))

        let recalled = MerchantMemory.lastCategory(forMerchant: "BLUE BOTTLE #4412", in: context)
        XCTAssertEqual(recalled?.name, "Coffee")
    }

    /// Most recent, not most frequent — a correction should take effect at
    /// once rather than waiting to outvote history.
    func testMostRecentWinsOverMostFrequent() {
        let coffee = Category(name: "Coffee")
        let dining = Category(name: "Dining out")
        context.insert(coffee)
        context.insert(dining)

        insert(merchant: "Terroni", category: coffee, date: TestSupport.date(2026, 8, 1))
        insert(merchant: "Terroni", category: coffee, date: TestSupport.date(2026, 8, 2))
        insert(merchant: "Terroni", category: dining, date: TestSupport.date(2026, 8, 3))

        XCTAssertEqual(MerchantMemory.lastCategory(forMerchant: "Terroni", in: context)?.name, "Dining out")
    }

    /// Skips past uncategorised records rather than giving up at the first one.
    func testSkipsUncategorisedRecords() {
        let coffee = Category(name: "Coffee")
        context.insert(coffee)

        insert(merchant: "Blue Bottle", category: coffee, date: TestSupport.date(2026, 8, 1))
        insert(merchant: "Blue Bottle", category: nil, date: TestSupport.date(2026, 8, 5))

        XCTAssertEqual(MerchantMemory.lastCategory(forMerchant: "Blue Bottle", in: context)?.name, "Coffee")
    }

    func testUnknownMerchantRecallsNothing() {
        XCTAssertNil(MerchantMemory.lastCategory(forMerchant: "Never Seen", in: context))
    }

    func testEmptyMerchantRecallsNothing() {
        let coffee = Category(name: "Coffee")
        context.insert(coffee)
        insert(merchant: "Blue Bottle", category: coffee, date: TestSupport.date(2026, 8, 1))

        XCTAssertNil(MerchantMemory.lastCategory(forMerchant: "", in: context))
        XCTAssertNil(MerchantMemory.lastCategory(forMerchant: "   ", in: context))
    }

    // MARK: The line it must not cross

    /// Memory fills in a category. It must never fill in a verdict — filing
    /// something under Coffee twice says nothing about whether the third one
    /// was worth it, and that judgement is the product. See D-002.
    func testMemoryOnlyReturnsCategoriesNotVerdicts() {
        let coffee = Category(name: "Coffee")
        context.insert(coffee)
        insert(merchant: "Blue Bottle", category: coffee, date: TestSupport.date(2026, 8, 1), verdict: .leak)
        insert(merchant: "Blue Bottle", category: coffee, date: TestSupport.date(2026, 8, 2), verdict: .leak)

        // The API surface has no way to return a verdict at all. This test
        // exists so that adding one becomes a deliberate, visible change.
        let recalled = MerchantMemory.lastCategory(forMerchant: "Blue Bottle", in: context)
        XCTAssertEqual(recalled?.name, "Coffee")
    }

    // MARK: Suggestions

    func testSuggestionsMatchByPrefix() {
        insert(merchant: "Blue Bottle", category: nil, date: TestSupport.date(2026, 8, 1))
        insert(merchant: "Loblaws", category: nil, date: TestSupport.date(2026, 8, 2))

        let suggestions = MerchantMemory.recentMerchants(matching: "blu", in: context)
        XCTAssertEqual(suggestions, ["Blue Bottle"])
    }

    func testSuggestionsDeduplicate() {
        for day in 1...5 {
            insert(merchant: "Blue Bottle", category: nil, date: TestSupport.date(2026, 8, day))
        }
        let suggestions = MerchantMemory.recentMerchants(matching: "blue", in: context)
        XCTAssertEqual(suggestions.count, 1)
    }

    func testEmptyQueryReturnsNoSuggestions() {
        insert(merchant: "Blue Bottle", category: nil, date: TestSupport.date(2026, 8, 1))
        XCTAssertTrue(MerchantMemory.recentMerchants(matching: "", in: context).isEmpty)
    }

    func testSuggestionsRespectLimit() {
        for (index, name) in ["Cafe A", "Cafe B", "Cafe C", "Cafe D"].enumerated() {
            insert(merchant: name, category: nil, date: TestSupport.date(2026, 8, index + 1))
        }
        XCTAssertEqual(MerchantMemory.recentMerchants(matching: "cafe", limit: 2, in: context).count, 2)
    }
}

/// The undo path and category assignment, both of which touch the two fields
/// that must never be collapsed into one.
@MainActor
final class SortActionsTests: XCTestCase {

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

    /// Undo has to restore both fields together. Restoring the verdict alone
    /// would leave a confirmed transaction with no judgement — counted in
    /// totals, invisible in the queue.
    func testUndoRestoresBothFields() {
        let transaction = Transaction(amount: 20, merchant: "Cafe", source: .applePay)
        context.insert(transaction)

        let previousVerdict = transaction.verdict
        let previousConfirmed = transaction.isConfirmed

        transaction.verdict = .leak
        transaction.isConfirmed = true

        transaction.verdict = previousVerdict
        transaction.isConfirmed = previousConfirmed

        XCTAssertEqual(transaction.verdict, .unrated)
        XCTAssertFalse(transaction.isConfirmed)
        XCTAssertTrue(transaction.needsSorting)
    }

    /// Categorising is filing. Confirming is judgement. A tap must not do both.
    func testAssigningCategoryDoesNotConfirm() {
        let category = Category(name: "Coffee")
        let transaction = Transaction(amount: 5, merchant: "Blue Bottle", source: .applePay)
        context.insert(category)
        context.insert(transaction)

        transaction.category = category
        try? context.save()

        XCTAssertEqual(transaction.category?.name, "Coffee")
        XCTAssertFalse(transaction.isConfirmed)
        XCTAssertEqual(transaction.verdict, .unrated)
        XCTAssertTrue(transaction.needsSorting)
    }

    func testCategorisedTransactionStaysInTheQueue() throws {
        let category = Category(name: "Coffee")
        let transaction = Transaction(amount: 5, merchant: "Blue Bottle", source: .applePay)
        context.insert(category)
        context.insert(transaction)
        transaction.category = category
        try context.save()

        let queued = try context.fetch(
            FetchDescriptor<Transaction>(
                predicate: #Predicate { !$0.isConfirmed && !$0.isSuperseded }
            )
        )
        XCTAssertEqual(queued.count, 1)
    }
}
