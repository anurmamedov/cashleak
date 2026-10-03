import XCTest
import SwiftData
@testable import cashleak

/// History is kept; only merged duplicates expire, and old purchases go only
/// when asked (D-028).
@MainActor
final class HistoryMaintenanceTests: XCTestCase {

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

    private let now = TestSupport.date(2026, 10, 3)

    private func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 24 * 60 * 60)
    }

    func testOldMergedDuplicatesArePurged() throws {
        let old = TestSupport.confirmed(5, verdict: .leak, date: daysAgo(120))
        old.isSuperseded = true
        context.insert(old)
        try context.save()

        XCTAssertEqual(HistoryMaintenance.purgeOldMergedDuplicates(now: now, in: context), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 0)
    }

    /// Recent ones stay — a wrong merge might still be spotted.
    func testRecentMergedDuplicatesStay() throws {
        let recent = TestSupport.confirmed(5, verdict: .leak, date: daysAgo(30))
        recent.isSuperseded = true
        context.insert(recent)
        try context.save()

        XCTAssertEqual(HistoryMaintenance.purgeOldMergedDuplicates(now: now, in: context), 0)
    }

    /// Real purchases are never purged automatically, however old.
    func testOldRealPurchasesAreNeverPurged() throws {
        context.insert(TestSupport.confirmed(5, verdict: .worthIt, date: daysAgo(900)))
        try context.save()

        HistoryMaintenance.purgeOldMergedDuplicates(now: now, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Transaction>()), 1)
    }

    func testOlderThanSelectsOnlyBeforeTheCutoff() {
        let cutoff = HistoryMaintenance.cutoff(for: .oneYear, now: now, calendar: TestSupport.torontoCalendar)
        let old = TestSupport.confirmed(5, verdict: .leak, date: daysAgo(400))
        let recent = TestSupport.confirmed(5, verdict: .leak, date: daysAgo(100))

        let picked = HistoryMaintenance.purchases(olderThan: cutoff, in: [old, recent])
        XCTAssertEqual(picked.count, 1)
        XCTAssertTrue(picked.first === old)
    }
}
