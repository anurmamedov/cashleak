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

    func testCaughtShareCountsPurchasesThatNeededNoTyping() {
        let stats = AccountData.stats(from: [
            Transaction(amount: 4.19, merchant: "Tim Hortons", source: .applePay),
            Transaction(amount: 1500, merchant: "Rent", source: .recurring),
            Transaction(amount: 48.27, merchant: "Loblaws", source: .scan),
            Transaction(amount: 12, merchant: "Market", source: .manual),
        ])
        XCTAssertEqual(stats.caughtShare ?? 0, 0.5, accuracy: 0.001)
    }

    func testMergedDuplicatesAreLeftOut() {
        let merged = Transaction(amount: 4.19, merchant: "Tim Hortons", source: .manual)
        merged.isSuperseded = true
        let stats = AccountData.stats(from: [
            Transaction(amount: 4.19, merchant: "Tim Hortons", source: .applePay),
            merged,
        ])
        XCTAssertEqual(stats.caughtShare ?? 0, 1, accuracy: 0.001)
    }

    func testWaitingIsWhatSortHolds() {
        let stats = AccountData.stats(from: [
            Transaction(amount: 4.19, merchant: "Tim Hortons", source: .applePay),
            Transaction(amount: 5.93, merchant: "Starbucks", source: .applePay),
            TestSupport.confirmed(30, verdict: .worthIt),
        ])
        XCTAssertEqual(stats.waiting, 2)
    }

    func testSinceIsTheEarliestPurchase() {
        let july = TestSupport.date(2026, 7, 4)
        let stats = AccountData.stats(from: [
            TestSupport.confirmed(5, verdict: .leak, date: TestSupport.date(2026, 9, 1)),
            Transaction(amount: 5, date: july, merchant: "Shop", source: .applePay),
        ])
        XCTAssertEqual(stats.since, july)
    }

    func testEmptyHistory() {
        let stats = AccountData.stats(from: [])
        XCTAssertNil(stats.caughtShare)
        XCTAssertEqual(stats.waiting, 0)
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
