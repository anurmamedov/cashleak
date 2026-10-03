import XCTest
import SwiftData
@testable import cashleak

/// Managing categories: no duplicates, honest delete messages, and renaming a
/// starter category not breaking automatic filing (D-027).
@MainActor
final class CategoryRulesTests: XCTestCase {

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

    private func categories() throws -> [cashleak.Category] {
        try context.fetch(FetchDescriptor<cashleak.Category>())
    }

    private func named(_ name: String) throws -> cashleak.Category {
        try XCTUnwrap(try categories().first { $0.name == name })
    }

    // MARK: Duplicates

    func testDuplicateNameIsCaughtIgnoringCaseAndSpaces() throws {
        let all = try categories()
        XCTAssertTrue(CategoryRules.isNameTaken("coffee ", among: all))
        XCTAssertFalse(CategoryRules.isNameTaken("Pets", among: all))
    }

    /// Saving a category under its own name isn't a duplicate.
    func testEditingKeepsItsOwnName() throws {
        let coffee = try named("Coffee")
        XCTAssertFalse(CategoryRules.isNameTaken("Coffee", among: try categories(), excluding: coffee))
    }

    // MARK: Delete

    func testDeleteMessageCountsPurchases() throws {
        let coffee = try named("Coffee")
        XCTAssertEqual(CategoryRules.deleteMessage(for: coffee), "It has no purchases.")

        context.insert(TestSupport.confirmed(4.19, verdict: .leak, category: coffee))
        context.insert(TestSupport.confirmed(6.25, verdict: .leak, category: coffee))
        try context.save()
        XCTAssertTrue(CategoryRules.deleteMessage(for: coffee).hasPrefix("2 purchases"))
    }

    /// Purchases outlive their category.
    func testDeletingKeepsPurchasesUncategorised() throws {
        let coffee = try named("Coffee")
        let purchase = TestSupport.confirmed(4.19, verdict: .leak, category: coffee)
        context.insert(purchase)
        try context.save()

        CategoryRules.delete(coffee, in: context)

        let left = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(left.count, 1)
        XCTAssertNil(left.first?.category)
    }

    // MARK: Renamed starter categories

    /// Coffee renamed Café still collects Tim Hortons.
    func testRenamedStarterCategoryKeepsAutomaticFiling() throws {
        let coffee = try named("Coffee")
        coffee.name = "Café"
        try context.save()

        TransactionIngest.ingest(amount: 4.19, merchant: "Tim Hortons", source: .applePay, into: context)

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertEqual(stored.category?.name, "Café")
    }

    func testStarterCategoriesRememberWhatTheyWere() throws {
        XCTAssertEqual(try named("Groceries").builtInName, "Groceries")
    }

    /// A category someone made themselves isn't a starter one.
    func testUserCategoriesHaveNoBuiltInName() throws {
        let pets = cashleak.Category(name: "Pets")
        context.insert(pets)
        XCTAssertEqual(pets.builtInName, "")
    }
}
