/// Goals and CSV export.
final class GoalsAndExportTests: XCTestCase {

    private let calendar = TestSupport.torontoCalendar
    private let now = TestSupport.date(2026, 8, 20)

    // MARK: Goal trade-off

    /// The line that makes a leak total mean something.
    func testShareBelowOneHundredReadsAsAPercentage() {
        let goal = Goal(name: "Lisbon", targetAmount: 1200)
        XCTAssertEqual(goal.tradeOffLine(leaked: 412), "That's 34% of Lisbon.")
    }

    /// Past 100% a percentage stops being a trade-off and becomes arithmetic.
    func testAboveOneHundredReadsAsMoreThan() {
        let goal = Goal(name: "a new lens", targetAmount: 300)
        XCTAssertEqual(goal.tradeOffLine(leaked: 420), "That's more than a new lens.")
    }

    func testAboveTwoHundredCountsWholeGoals() {
        let goal = Goal(name: "Lisbon", targetAmount: 200)
        XCTAssertEqual(goal.tradeOffLine(leaked: 700), "That's 3 × Lisbon.")
    }

    /// Rounding down, so the app never overstates its own point.
    func testGoalCountRoundsDown() {
        let goal = Goal(name: "Lisbon", targetAmount: 200)
        XCTAssertEqual(goal.tradeOffLine(leaked: 590), "That's 2 × Lisbon.")
    }

    func testNoLineWithoutALeak() {
        XCTAssertNil(Goal(name: "Lisbon", targetAmount: 1200).tradeOffLine(leaked: 0))
    }

    func testNoLineWithoutATarget() {
        XCTAssertNil(Goal(name: "Someday", targetAmount: 0).tradeOffLine(leaked: 400))
    }

    /// A rounding-to-zero share says nothing worth saying.
    func testNoLineWhenShareRoundsToZero() {
        XCTAssertNil(Goal(name: "A house", targetAmount: 500_000).tradeOffLine(leaked: 1))
    }

    // MARK: Choosing a goal

    func testCurrentPrefersTheActiveGoal() {
        let a = Goal(name: "Camera", targetAmount: 900, isActive: false)
        let b = Goal(name: "Lisbon", targetAmount: 1200, isActive: true)
        XCTAssertEqual(GoalStore.current(from: [a, b])?.name, "Lisbon")
    }

    /// Something already reached shouldn't keep haunting the hero line.
    func testCurrentSkipsAchievedGoals() {
        let done = Goal(name: "Camera", targetAmount: 900)
        done.achievedAt = .now
        let live = Goal(name: "Lisbon", targetAmount: 1200, isActive: false)
        XCTAssertEqual(GoalStore.current(from: [done, live])?.name, "Lisbon")
    }

    func testCurrentIgnoresGoalsWithNoTarget() {
        let vague = Goal(name: "Someday", targetAmount: 0)
        XCTAssertNil(GoalStore.current(from: [vague]))
    }

    func testCurrentFallsBackWhenNothingIsActive() {
        let a = Goal(name: "Camera", targetAmount: 900, isActive: false)
        XCTAssertEqual(GoalStore.current(from: [a])?.name, "Camera")
    }

    func testNoGoalsMeansNoCurrent() {
        XCTAssertNil(GoalStore.current(from: []))
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
