import XCTest
import SwiftData
@testable import cashleak

/// The category suggestion table, and the rules that keep it from overreaching.
///
/// Two things are being protected here. The first is that the table guesses
/// well enough to be worth having. The second — the one that matters more — is
/// that it only ever guesses a *category*, and always loses to the user.
@MainActor
final class MerchantCategoryHintsTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try TestSupport.makeContainer()
        context = ModelContext(container)
        SeedData.seedCategoriesIfNeeded(in: context)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    // MARK: The table

    /// The merchants from the real Wallet feed that prompted this.
    func testSuggestsForObservedWalletMerchants() {
        let cases: [(String, String)] = [
            ("Tim Hortons", "Coffee"),
            ("No Frills", "Groceries"),
            ("Sobeys", "Groceries"),
            ("Walmart Supercentre", "Groceries"),
            ("Canadian Tire", "Shopping"),
            ("Hatsu Sushi", "Dining out"),
            ("Apple", "Shopping"),
        ]

        for (merchant, expected) in cases {
            XCTAssertEqual(
                MerchantCategoryHints.categoryName(forMerchant: merchant),
                expected,
                "\(merchant) should suggest \(expected)"
            )
        }
    }

    /// `Solmaz` is in the observed feed and in no table. An unknown merchant has
    /// to return nothing rather than reach for the nearest fragment.
    func testUnknownMerchantSuggestsNothing() {
        XCTAssertNil(MerchantCategoryHints.categoryName(forMerchant: "Solmaz"))
        XCTAssertNil(MerchantCategoryHints.categoryName(forMerchant: ""))
        XCTAssertNil(MerchantCategoryHints.categoryName(forMerchant: "   "))
    }

    /// The specific fragment has to beat the general one no matter where either
    /// sits in the table.
    func testLongestFragmentWins() {
        XCTAssertEqual(MerchantCategoryHints.categoryName(forMerchant: "Uber Eats"), "Delivery")
        XCTAssertEqual(MerchantCategoryHints.categoryName(forMerchant: "Uber"), "Transit")
    }

    /// Whole words only. A substring match would file a barber under Dining out
    /// on the strength of "bar", and a wrong category is worse than none — the
    /// user has no reason to go looking for it.
    func testMatchesWholeWordsOnly() {
        XCTAssertNil(MerchantCategoryHints.categoryName(forMerchant: "Barber Shop"))
        XCTAssertNil(MerchantCategoryHints.categoryName(forMerchant: "Pineapple Express"))
        XCTAssertNil(MerchantCategoryHints.categoryName(forMerchant: "Metropolis Comics"))
    }

    /// Wallet sends title case; the table is lowercase.
    func testCaseAndPunctuationInsensitive() {
        XCTAssertEqual(MerchantCategoryHints.categoryName(forMerchant: "TIM HORTONS"), "Coffee")
        XCTAssertEqual(MerchantCategoryHints.categoryName(forMerchant: "tim hortons"), "Coffee")
        XCTAssertEqual(MerchantCategoryHints.categoryName(forMerchant: "McDonald's"), "Dining out")
    }

    // MARK: Applied at ingest

    func testIngestFillsCategoryFromTable() throws {
        TransactionIngest.ingest(
            amount: 4.19, merchant: "Tim Hortons", source: .applePay, into: context
        )

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertEqual(stored.category?.name, "Coffee")
    }

    /// The suggestion is a filing convenience and nothing more. If it ever also
    /// set a verdict or confirmed the record, the app would be judging spending
    /// on the user's behalf — which is the one thing it must not do (D-002).
    func testSuggestionNeverConfirmsOrJudges() throws {
        TransactionIngest.ingest(
            amount: 4.19, merchant: "Tim Hortons", source: .applePay, into: context
        )

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertNotNil(stored.category)
        XCTAssertFalse(stored.isConfirmed)
        XCTAssertEqual(stored.verdict, .unrated)
        XCTAssertTrue(stored.needsSorting)
    }

    /// One correction has to stick. The user filing Tim Hortons under Dining out
    /// must outrank the table forever after, or the app argues with them daily.
    func testUserHistoryBeatsTheTable() throws {
        let dining = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Category>())
                .first { $0.name == "Dining out" }
        )

        let corrected = TestSupport.confirmed(
            9.99,
            verdict: .worthIt,
            date: .now.addingTimeInterval(-60 * 60 * 24 * 30),
            merchant: "Tim Hortons",
            category: dining
        )
        context.insert(corrected)
        try context.save()

        TransactionIngest.ingest(
            amount: 4.19, merchant: "Tim Hortons", source: .applePay, into: context
        )

        let fresh = try context.fetch(FetchDescriptor<Transaction>())
            .first { $0.amount == 4.19 }
        XCTAssertEqual(fresh?.category?.name, "Dining out")
    }

    /// The table names categories; it never creates them. Someone who deleted
    /// or renamed Coffee gets no category, not a resurrected one.
    func testMissingCategoryIsNotRecreated() throws {
        let coffee = try XCTUnwrap(
            try context.fetch(FetchDescriptor<Category>()).first { $0.name == "Coffee" }
        )
        context.delete(coffee)
        try context.save()

        TransactionIngest.ingest(
            amount: 4.19, merchant: "Tim Hortons", source: .applePay, into: context
        )

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertNil(stored.category)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<Category>()).filter { $0.name == "Coffee" }.count,
            0
        )
    }

    func testUnknownMerchantLeavesCategoryEmpty() throws {
        TransactionIngest.ingest(
            amount: 17.65, merchant: "Solmaz", source: .applePay, into: context
        )

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertNil(stored.category)
    }
}
