import XCTest
import SwiftData
@testable import cashleak

/// New purchases carry the currency chosen in Profile, so the CSV export
/// stops saying CAD for someone spending in dollars or euros.
@MainActor
final class IngestCurrencyTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var savedCurrency: String!

    override func setUp() async throws {
        container = try TestSupport.makeContainer()
        context = ModelContext(container)
        savedCurrency = AppSettings.currencyCode
    }

    override func tearDown() async throws {
        AppSettings.currencyCode = savedCurrency
        container = nil
        context = nil
    }

    func testIngestStampsTheChosenCurrency() throws {
        AppSettings.currencyCode = "USD"
        TransactionIngest.ingest(amount: 5.93, merchant: "Starbucks", source: .manual, into: context)
        let saved = try XCTUnwrap(try context.fetch(FetchDescriptor<Transaction>()).first)
        XCTAssertEqual(saved.currencyCode, "USD")
        XCTAssertTrue(CSVExport.makeCSV(from: [saved]).contains(",USD,"))
    }
}
