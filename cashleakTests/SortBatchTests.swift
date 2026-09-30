import XCTest
import SwiftData
@testable import cashleak

/// Bulk actions in Sort.
///
/// Each of these can go wrong without anything looking wrong: an undo that
/// forgets the category, a bulk category that silently confirms, a removal
/// that leaves a record counting. The totals would just be off.
@MainActor
final class SortBatchTests: XCTestCase {

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

    private func unsorted(_ amount: Double, _ merchant: String = "Tim Hortons") -> Transaction {
        let transaction = Transaction(amount: amount, merchant: merchant, source: .applePay)
        context.insert(transaction)
        return transaction
    }

    /// A bulk verdict is a swipe applied to each: verdict set and confirmed.
    func testApplySetsVerdictAndConfirms() {
        let items = [unsorted(4.19), unsorted(6.25)]
        SortBatch.apply(.leak, to: items)

        XCTAssertTrue(items.allSatisfy { $0.verdict == .leak && $0.isConfirmed })
        XCTAssertTrue(items.allSatisfy(\.countsTowardTotals))
    }

    /// Filing is not judging. A bulk category must leave everything in Sort.
    func testAssignDoesNotConfirm() {
        let coffee = cashleak.Category(name: "Coffee")
        context.insert(coffee)
        let items = [unsorted(4.19), unsorted(6.25)]

        SortBatch.assign(coffee, to: items)

        XCTAssertTrue(items.allSatisfy { $0.category?.name == "Coffee" })
        XCTAssertTrue(items.allSatisfy(\.needsSorting))
    }

    /// Undo puts back all three fields, including a category that was changed
    /// in the same action.
    func testRestoreUndoesVerdictConfirmationAndCategory() {
        let dining = cashleak.Category(name: "Dining out")
        let coffee = cashleak.Category(name: "Coffee")
        context.insert(dining)
        context.insert(coffee)

        let item = unsorted(4.19)
        item.category = dining
        let snapshots = SortBatch.snapshot([item])

        SortBatch.apply(.worthIt, to: [item])
        SortBatch.assign(coffee, to: [item])
        SortBatch.restore(snapshots)

        XCTAssertEqual(item.verdict, .unrated)
        XCTAssertFalse(item.isConfirmed)
        XCTAssertEqual(item.category?.name, "Dining out")
    }

    func testRemoveDeletesOnlyTheChosenOnes() throws {
        let keep = unsorted(44.65, "No Frills")
        let testRuns = [unsorted(335.40, ""), unsorted(11.40, "")]
        try context.save()

        SortBatch.remove(testRuns, in: context)

        let left = try context.fetch(FetchDescriptor<Transaction>())
        XCTAssertEqual(left.count, 1)
        XCTAssertEqual(left.first?.persistentModelID, keep.persistentModelID)
    }

    /// Removing a purchase never touches the capture log — it records what
    /// arrived, not what you kept.
    func testRemoveLeavesTheCaptureLogAlone() throws {
        let item = unsorted(4.19)
        CaptureLog.record(rawMerchant: "Tim Hortons", amount: 4.19, source: .applePay, outcome: "inserted", in: context)

        SortBatch.remove([item], in: context)

        XCTAssertEqual(try context.fetch(FetchDescriptor<CaptureLogEntry>()).count, 1)
    }
}
