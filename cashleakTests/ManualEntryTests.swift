import XCTest
import SwiftData
@testable import cashleak

/// The Add sheet now writes through `TransactionIngest` (D-034), and shows what
/// the user said before at a merchant without choosing for them (D-035).
@MainActor
final class ManualEntryTests: XCTestCase {

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

    // MARK: Confirmation

    func testManualEntryWithVerdictIsConfirmed() throws {
        let result = TransactionIngest.ingest(
            amount: 4.19, merchant: "Tim Hortons", source: .manual,
            personVerdict: .leak, into: context
        )
        XCTAssertEqual(result, .inserted)
        let saved = try XCTUnwrap(try stored().first)
        XCTAssertTrue(saved.isConfirmed)
        XCTAssertEqual(saved.verdict, .leak)
        XCTAssertTrue(saved.countsTowardTotals)
    }

    func testManualEntryLeftForLaterWaitsInSort() throws {
        TransactionIngest.ingest(amount: 4.19, merchant: "Tim Hortons", source: .manual, into: context)
        let saved = try XCTUnwrap(try stored().first)
        XCTAssertFalse(saved.isConfirmed)
        XCTAssertTrue(saved.needsSorting)
    }

    /// The rule that matters most: no capture source can arrive confirmed,
    /// whatever it passes.
    func testCaptureSourcesIgnoreAVerdict() throws {
        for (index, source) in [TransactionSource.applePay, .bankAlert, .recurring].enumerated() {
            TransactionIngest.ingest(
                amount: Double(10 + index), merchant: "Shop \(source.rawValue)",
                source: source, personVerdict: .worthIt, into: context
            )
        }
        for transaction in try stored() {
            XCTAssertFalse(transaction.isConfirmed, "\(transaction.merchant) arrived confirmed")
            XCTAssertEqual(transaction.verdict, .unrated)
        }
    }

    func testUnratedPassedAsVerdictStaysUnconfirmed() throws {
        TransactionIngest.ingest(
            amount: 9, merchant: "Loblaws", source: .manual,
            personVerdict: .unrated, into: context
        )
        XCTAssertFalse(try XCTUnwrap(try stored().first).isConfirmed)
    }

    func testChosenCategoryIsKept() throws {
        let dining = cashleak.Category(name: "Dining")
        context.insert(dining)
        TransactionIngest.ingest(
            amount: 4.19, merchant: "Tim Hortons", source: .manual,
            category: dining, into: context
        )
        XCTAssertEqual(try XCTUnwrap(try stored().first).category?.name, "Dining")
    }

    // MARK: Dedup — the bug this fixes

    /// Wallet caught it, then the user typed it too. One purchase, counted once,
    /// and the verdict typed on the sheet lands on whichever record survives.
    func testTypingAPurchaseWalletCaughtMergesAndKeepsTheVerdict() throws {
        let tap = TestSupport.date(2026, 10, 3, hour: 8)
        TransactionIngest.ingest(amount: 4.19, merchant: "Tim Hortons", date: tap, source: .applePay, into: context)

        let result = TransactionIngest.ingest(
            amount: 4.19, merchant: "Tim Hortons", date: tap.addingTimeInterval(3 * 3600),
            source: .manual, personVerdict: .leak, into: context
        )

        XCTAssertEqual(result, .duplicate)
        let survivors = try active()
        XCTAssertEqual(survivors.count, 1)
        XCTAssertTrue(survivors[0].isConfirmed)
        XCTAssertEqual(survivors[0].verdict, .leak)
    }

    func testLaterEntryMergingWithASortedOneKeepsTheEarlierAnswer() throws {
        let tap = TestSupport.date(2026, 10, 3, hour: 8)
        TransactionIngest.ingest(amount: 12, merchant: "Loblaws", date: tap, source: .applePay, into: context)
        let first = try XCTUnwrap(try stored().first)
        first.verdict = .worthIt
        first.isConfirmed = true

        TransactionIngest.ingest(
            amount: 12, merchant: "Loblaws", date: tap.addingTimeInterval(3600),
            source: .manual, into: context
        )

        let survivors = try active()
        XCTAssertEqual(survivors.count, 1)
        XCTAssertEqual(survivors[0].verdict, .worthIt)
        XCTAssertTrue(survivors[0].isConfirmed)
    }

    // MARK: Verdict history (D-035)

    private func rated(_ verdict: Verdict, daysAgo: Int, merchant: String = "Tim Hortons") {
        let t = Transaction(
            amount: Double(daysAgo) + 1, date: .now.addingTimeInterval(-Double(daysAgo) * 86_400),
            merchant: merchant, source: .applePay, verdict: verdict, isConfirmed: true
        )
        context.insert(t)
        try? context.save()
    }

    func testHistoryStaysSilentBelowThreeRatedVisits() {
        rated(.leak, daysAgo: 1)
        rated(.leak, daysAgo: 2)
        XCTAssertNil(MerchantMemory.verdictHistory(forMerchant: "Tim Hortons", in: context))
    }

    func testHistoryCountsTheLastFiveRatedVisits() throws {
        rated(.leak, daysAgo: 1)
        rated(.leak, daysAgo: 2)
        rated(.worthIt, daysAgo: 3)
        rated(.leak, daysAgo: 4)
        rated(.leak, daysAgo: 5)
        rated(.worthIt, daysAgo: 6)   // sixth: outside the window
        rated(.unrated, daysAgo: 0)   // unrated: never counted

        let history = try XCTUnwrap(MerchantMemory.verdictHistory(forMerchant: "Tim Hortons", in: context))
        XCTAssertEqual(history, .init(leak: 4, worthIt: 1))
        XCTAssertEqual(history.summary, "Last 5 times here: 4 leak · 1 worth it")
    }

    func testHistoryIgnoresOtherMerchants() {
        rated(.leak, daysAgo: 1, merchant: "Starbucks")
        rated(.leak, daysAgo: 2, merchant: "Starbucks")
        rated(.leak, daysAgo: 3, merchant: "Starbucks")
        XCTAssertNil(MerchantMemory.verdictHistory(forMerchant: "Tim Hortons", in: context))
    }

    func testSummaryLeavesOutAZeroSide() {
        XCTAssertEqual(
            MerchantMemory.VerdictHistory(leak: 0, worthIt: 3).summary,
            "Last 3 times here: 3 worth it"
        )
    }
}
