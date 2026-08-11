import XCTest
@testable import cashleak

/// Trip forecasting, the city index, discretionary averaging, and CSV export.
final class TripsAndExportTests: XCTestCase {

    private let calendar = TestSupport.torontoCalendar
    private let now = TestSupport.date(2026, 8, 20)

    // MARK: City index

    func testEveryMultiplierIsPlausible() {
        for city in CityCostIndex.cities {
            XCTAssertGreaterThan(city.multiplier, 0.2, "\(city.name) is implausibly cheap")
            XCTAssertLessThan(city.multiplier, 2.5, "\(city.name) is implausibly expensive")
        }
    }

    func testBaselineCityIsExactlyOne() {
        XCTAssertEqual(CityCostIndex.city(named: "Toronto")?.multiplier, 1.0)
    }

    func testNoDuplicateCities() {
        let ids = CityCostIndex.cities.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testSearchMatchesNameAndCountry() {
        XCTAssertTrue(CityCostIndex.search("lisb").contains { $0.name == "Lisbon" })
        XCTAssertTrue(CityCostIndex.search("portugal").contains { $0.name == "Porto" })
        XCTAssertEqual(CityCostIndex.search("").count, CityCostIndex.cities.count)
    }

    func testComparisonReadsNaturally() {
        XCTAssertEqual(CityCostIndex.comparison(for: 1.0), "about the same as Toronto")
        XCTAssertTrue(CityCostIndex.comparison(for: 0.8).contains("20% less"))
        XCTAssertTrue(CityCostIndex.comparison(for: 1.35).contains("35% more"))
    }

    // MARK: Forecast

    func testForecastMatchesTheStatedFormula() {
        let trip = Trip(
            name: "Lisbon", destination: "Lisbon",
            startDate: TestSupport.date(2026, 10, 1),
            endDate: TestSupport.date(2026, 10, 11),
            fixedCosts: 900, costMultiplier: 0.8,
            dailyDiscretionaryAtEstimate: 34
        )
        // 34 × 0.8 × 10 + 900
        XCTAssertEqual(trip.estimatedBudget, 1172, accuracy: 0.01)
        XCTAssertEqual(trip.dailyAllowance, 27.2, accuracy: 0.01)
    }

    /// The snapshot exists so a past trip's estimate doesn't drift as later
    /// spending changes the average.
    func testEstimateDoesNotDriftWithLaterSpending() {
        let trip = Trip(
            name: "Past", startDate: TestSupport.date(2026, 1, 1),
            endDate: TestSupport.date(2026, 1, 8),
            costMultiplier: 1.0, dailyDiscretionaryAtEstimate: 30
        )
        let before = trip.estimatedBudget
        XCTAssertEqual(trip.estimatedBudget, before)
    }

    // MARK: Discretionary average

    /// Rent would triple the daily figure and make every forecast useless.
    func testFixedCostCategoriesAreExcluded() {
        let rent = Category(name: "Rent")
        let coffee = Category(name: "Coffee")

        var data = (1...25).map { day in
            Transaction(
                amount: 10, date: TestSupport.date(2026, 8, min(day, 28)),
                merchant: "Cafe", source: .manual, verdict: .worthIt,
                isConfirmed: true, category: coffee
            )
        }
        data.append(Transaction(
            amount: 2100, date: TestSupport.date(2026, 8, 1),
            merchant: "Rent", source: .recurring, verdict: .worthIt,
            isConfirmed: true, category: rent
        ))

        let average = DiscretionarySpend.dailyAverage(from: data, now: now, calendar: calendar)
        XCTAssertNotNil(average)
        XCTAssertLessThan(average ?? 999, 100)
    }

    /// A forecast built on four days of data would be confidently wrong.
    func testReturnsNilBelowTwentyTransactions() {
        let data = (1...19).map { day in
            Transaction(
                amount: 10, date: TestSupport.date(2026, 8, day),
                merchant: "Cafe", source: .manual, isConfirmed: true
            )
        }
        XCTAssertNil(DiscretionarySpend.dailyAverage(from: data, now: now, calendar: calendar))
    }

    func testUnconfirmedExcludedFromAverage() {
        let data = (1...25).map { day in
            Transaction(
                amount: 1000, date: TestSupport.date(2026, 8, min(day, 28)),
                merchant: "Cafe", source: .applePay, isConfirmed: false
            )
        }
        XCTAssertNil(DiscretionarySpend.dailyAverage(from: data, now: now, calendar: calendar))
    }

    // MARK: CSV

    func testCSVHasHeaderAndOneRowPerTransaction() {
        let csv = CSVExport.makeCSV(from: [
            TestSupport.confirmed(10, verdict: .leak, merchant: "A"),
            TestSupport.confirmed(20, verdict: .worthIt, merchant: "B"),
        ])
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(String(lines[0]), CSVExport.header)
    }

    /// Real merchant strings contain commas, quotes, and occasionally newlines.
    func testFieldsWithCommasAreQuoted() {
        XCTAssertEqual(CSVExport.escape("Loblaws, Toronto"), "\"Loblaws, Toronto\"")
        XCTAssertEqual(CSVExport.escape("plain"), "plain")
        XCTAssertEqual(CSVExport.escape("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    /// Hiding merged rows would make the export disagree with the app.
    func testSupersededRowsAreIncludedAndFlagged() {
        let merged = TestSupport.confirmed(10, verdict: .leak, merchant: "Dup")
        merged.isSuperseded = true

        let csv = CSVExport.makeCSV(from: [merged])
        XCTAssertTrue(csv.contains("true"))
        XCTAssertEqual(csv.split(separator: "\n").count, 2)
    }

    func testCSVIsChronological() {
        let csv = CSVExport.makeCSV(from: [
            TestSupport.confirmed(10, verdict: .leak, date: TestSupport.date(2026, 8, 20), merchant: "Later"),
            TestSupport.confirmed(10, verdict: .leak, date: TestSupport.date(2026, 8, 1), merchant: "Earlier"),
        ])
        let lines = csv.split(separator: "\n")
        XCTAssertTrue(lines[1].contains("Earlier"))
        XCTAssertTrue(lines[2].contains("Later"))
    }

    // MARK: Card automation

    func testUnconfiguredCardIsNeverStale() {
        let card = CardAutomation(label: "Amex", isConfigured: false)
        XCTAssertFalse(card.looksStale)
        XCTAssertEqual(card.statusText, "Not set up")
    }

    func testConfiguredCardWithRecentCaptureIsActive() {
        let card = CardAutomation(label: "Visa", isConfigured: true)
        card.lastCapturedAt = .now
        XCTAssertFalse(card.looksStale)
        XCTAssertEqual(card.statusText, "Automation active")
    }

    /// Automations break silently when iOS updates. Surfacing that is the whole
    /// point of tracking capture time.
    func testConfiguredCardGoesStaleAfterTwoWeeks() {
        let card = CardAutomation(label: "Visa", isConfigured: true)
        card.lastCapturedAt = Date.now.addingTimeInterval(-20 * 86_400)
        XCTAssertTrue(card.looksStale)
        XCTAssertEqual(card.statusText, "No activity in 2 weeks")
    }
}
