import XCTest
import SwiftData
@testable import cashleak

/// The Profile card's numbers, and "Delete account" erasing what it says it
/// erases.
@MainActor
final class AccountDataTests: XCTestCase {

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

    func testStatsCountOnlySortedPurchases() {
        let unsorted = Transaction(amount: 4.19, merchant: "Tim Hortons", source: .applePay)
        let stats = AccountData.stats(from: [
            TestSupport.confirmed(30, verdict: .worthIt),
            TestSupport.confirmed(10, verdict: .leak),
            unsorted,
        ])
        XCTAssertEqual(stats.sorted, 2)
        XCTAssertEqual(stats.worthItShare ?? 0, 0.75, accuracy: 0.001)
    }

    func testNoShareBeforeAnyVerdict() {
        let stats = AccountData.stats(from: [TestSupport.confirmed(30, verdict: .unrated)])
        XCTAssertNil(stats.worthItShare)
    }

    func testSinceIsTheEarliestSortedPurchase() {
        let july = TestSupport.date(2026, 7, 4)
        let stats = AccountData.stats(from: [
            TestSupport.confirmed(5, verdict: .leak, date: TestSupport.date(2026, 9, 1)),
            TestSupport.confirmed(5, verdict: .leak, date: july),
        ])
        XCTAssertEqual(stats.since, july)
    }

    func testEmptyHistory() {
        let stats = AccountData.stats(from: [])
        XCTAssertEqual(stats.sorted, 0)
        XCTAssertNil(stats.since)
    }

    /// "Erase my spending" means all of it, not just purchases.
    func testEraseEverythingLeavesNothing() throws {
        context.insert(TestSupport.confirmed(5, verdict: .leak))
        context.insert(cashleak.Category(name: "Coffee"))
        context.insert(Goal(name: "Lisbon", targetAmount: 1200))
        CaptureLog.record(rawMerchant: "Tim Hortons", amount: 4.19, source: .applePay, outcome: "inserted", in: context)
        try context.save()

        AccountData.eraseEverything(in: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<cashleak.Category>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Goal>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CaptureLogEntry>()), 0)
    }
}
