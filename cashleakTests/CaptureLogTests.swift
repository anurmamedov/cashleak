import XCTest
import SwiftData
@testable import cashleak

/// The L3 collection harness.
///
/// It doesn't run L3 — that needs a card and a terminal. It makes sure that
/// when L3 does run, the data survives correctly instead of being retyped off
/// a screen.
@MainActor
final class CaptureLogTests: XCTestCase {

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

    private func entries() throws -> [CaptureLogEntry] {
        try context.fetch(FetchDescriptor<CaptureLogEntry>())
    }

    // MARK: Recording

    /// The raw string is the deliverable. Trimming or normalizing it on the way
    /// in would destroy the only copy of what actually arrived.
    func testRawStringIsStoredUntouched() throws {
        CaptureLog.record(
            rawMerchant: "  SQ *BLUE BOTTLE #22  ",
            amount: 6.75, source: .applePay, outcome: "inserted", in: context
        )

        let entry = try XCTUnwrap(try entries().first)
        XCTAssertEqual(entry.rawMerchant, "  SQ *BLUE BOTTLE #22  ")
    }

    /// Normalization is recorded at capture time so a later rule change doesn't
    /// silently rewrite what the log says happened.
    func testNormalizedFormIsCapturedAlongside() throws {
        CaptureLog.record(
            rawMerchant: "SQ *BLUE BOTTLE #22",
            amount: 6.75, source: .applePay, outcome: "inserted", in: context
        )

        let entry = try XCTUnwrap(try entries().first)
        XCTAssertEqual(entry.normalizedAtCapture, "blue bottle")
        XCTAssertTrue(entry.wasTransformed)
    }

    /// A string the normalizer leaves alone is worth spotting — it means the
    /// rules did nothing, which may or may not be right.
    func testUntransformedStringsAreFlagged() throws {
        CaptureLog.record(
            rawMerchant: "loblaws",
            amount: 20, source: .applePay, outcome: "inserted", in: context
        )
        XCTAssertFalse(try XCTUnwrap(try entries().first).wasTransformed)
    }

    /// A timed-out trigger delivers no merchant. That's a finding, not an
    /// error, so it still gets logged.
    func testEmptyMerchantIsStillRecorded() throws {
        CaptureLog.record(
            rawMerchant: nil, amount: 12,
            source: .applePay, outcome: "inserted", in: context
        )

        let entry = try XCTUnwrap(try entries().first)
        XCTAssertEqual(entry.rawMerchant, "")
        XCTAssertEqual(entry.normalizedAtCapture, "")
    }

    /// Declines are one of L3's questions, so a rejection must appear in the
    /// log rather than vanishing.
    func testRejectionsAreRecorded() throws {
        CaptureLog.record(
            rawMerchant: "DECLINED MERCHANT", amount: 0,
            source: .applePay, outcome: "rejected: nonPositiveAmount", in: context
        )

        let entry = try XCTUnwrap(try entries().first)
        XCTAssertTrue(entry.outcome.hasPrefix("rejected"))
    }

    // MARK: Trimming

    func testLogIsCappedAndKeepsTheNewest() throws {
        for index in 0..<(CaptureLog.limit + 15) {
            CaptureLog.record(
                rawMerchant: "Merchant \(index)", amount: Double(index + 1),
                source: .applePay, outcome: "inserted", in: context
            )
        }

        let all = try entries()
        XCTAssertLessThanOrEqual(all.count, CaptureLog.limit)
        XCTAssertTrue(all.contains { $0.rawMerchant == "Merchant \(CaptureLog.limit + 14)" })
    }

    func testClearRemovesEverything() throws {
        CaptureLog.record(rawMerchant: "A", amount: 1, source: .applePay, outcome: "inserted", in: context)
        CaptureLog.clear(in: context)
        XCTAssertTrue(try entries().isEmpty)
    }

    // MARK: Export

    func testExportProducesPasteableSwift() {
        let entries = [
            CaptureLogEntry(rawMerchant: "SQ *BLUE BOTTLE", amount: 6.75, source: .applePay, outcome: "inserted"),
            CaptureLogEntry(rawMerchant: "LOBLAWS #1043", amount: 88.40, source: .applePay, outcome: "inserted"),
        ]

        let export = CaptureLog.fixtureExport(entries)
        XCTAssertTrue(export.contains("merchantFixtures"))
        XCTAssertTrue(export.contains("(\"SQ *BLUE BOTTLE\", \"blue bottle\")"))
        XCTAssertTrue(export.contains("(\"LOBLAWS #1043\", \"loblaws\")"))
    }

    /// A merchant string containing a quote would produce Swift that doesn't
    /// compile.
    func testExportEscapesQuotes() {
        let entry = CaptureLogEntry(
            rawMerchant: "JOE\"S DINER", amount: 20, source: .applePay, outcome: "inserted"
        )
        XCTAssertTrue(CaptureLog.fixtureExport([entry]).contains("JOE\\\"S DINER"))
    }

    func testExportSkipsEmptyMerchants() {
        let entry = CaptureLogEntry(rawMerchant: "", amount: 20, source: .applePay, outcome: "inserted")
        let export = CaptureLog.fixtureExport([entry])
        XCTAssertFalse(export.contains("(\"\", "))
    }
}
