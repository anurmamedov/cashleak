import XCTest
@testable import cashleak

/// The week-by-week section of Analysis.
///
/// Weekly rollups are exactly the kind of arithmetic that looks right when it
/// isn't: a bar renders the same whether the boundary landed on Sunday or
/// Monday, whether a partial week was compared against a whole one, or whether
/// the "previous" week was actually a month earlier.
///
/// Dates are pinned to a fixed Wednesday, and the calendar's first weekday is
/// forced to Sunday, so the suite can't pass on one machine and fail on another.
final class WeekBreakdownTests: XCTestCase {

    /// Toronto, with the week starting Sunday — matching `Calendar.current` for
    /// an en_CA user, and fixed so CI in UTC agrees.
    private var calendar: Calendar {
        var calendar = TestSupport.torontoCalendar
        calendar.firstWeekday = 1
        return calendar
    }

    /// Wednesday 12 August 2026. Mid-week on purpose — the current week has to
    /// come out partial.
    private var now: Date {
        TestSupport.date(2026, 8, 12, calendar: calendar)
    }

    private func transaction(
        _ amount: Double,
        on date: Date,
        verdict: Verdict = .worthIt,
        confirmed: Bool = true
    ) -> Transaction {
        Transaction(
            amount: amount, date: date, merchant: "Test",
            source: .manual, verdict: verdict, isConfirmed: confirmed
        )
    }

    private func breakdown(_ transactions: [Transaction], limit: Int = 6)
        -> [AnalysisAggregates.WeekTotal] {
        AnalysisAggregates.weekBreakdown(
            transactions, range: .quarter, limit: limit, now: now, calendar: calendar
        )
    }

    // MARK: Grouping

    func testGroupsByCalendarWeekNotBySevenDayChunks() {
        // Sat 8 Aug and Sun 9 Aug are one day apart but in different weeks
        // when the week starts on Sunday.
        let saturday = TestSupport.date(2026, 8, 8, calendar: calendar)
        let sunday = TestSupport.date(2026, 8, 9, calendar: calendar)

        let weeks = breakdown([
            transaction(10, on: saturday),
            transaction(20, on: sunday),
        ])

        XCTAssertEqual(weeks.count, 2)
        XCTAssertEqual(weeks[0].spent, 20, accuracy: 0.001, "Newest week first")
        XCTAssertEqual(weeks[1].spent, 10, accuracy: 0.001)
    }

    func testSumsSpentLeakedAndCountWithinAWeek() throws {
        let monday = TestSupport.date(2026, 8, 3, calendar: calendar)
        let wednesday = TestSupport.date(2026, 8, 5, calendar: calendar)

        let weeks = breakdown([
            transaction(40, on: monday, verdict: .leak),
            transaction(60, on: wednesday, verdict: .worthIt),
            transaction(10, on: wednesday, verdict: .leak),
        ])

        let week = try XCTUnwrap(weeks.first { $0.count == 3 })
        XCTAssertEqual(week.spent, 110, accuracy: 0.001)
        XCTAssertEqual(week.leaked, 50, accuracy: 0.001)
        XCTAssertEqual(week.kept, 60, accuracy: 0.001)
        XCTAssertEqual(week.leakShare, 50.0 / 110.0, accuracy: 0.001)
    }

    func testExcludesUnconfirmedAndSuperseded() {
        let day = TestSupport.date(2026, 8, 3, calendar: calendar)

        let superseded = transaction(99, on: day)
        superseded.isSuperseded = true

        let weeks = breakdown([
            transaction(40, on: day),
            transaction(99, on: day, confirmed: false),
            superseded,
        ])

        XCTAssertEqual(weeks.count, 1)
        XCTAssertEqual(weeks[0].spent, 40, accuracy: 0.001)
        XCTAssertEqual(weeks[0].count, 1)
    }

    func testOmitsWeeksWithNoSpendRatherThanShowingZero() {
        let recent = TestSupport.date(2026, 8, 3, calendar: calendar)
        let old = TestSupport.date(2026, 7, 6, calendar: calendar)

        let weeks = breakdown([
            transaction(10, on: recent),
            transaction(10, on: old),
        ])

        // Four calendar weeks apart, but only the two with data appear.
        XCTAssertEqual(weeks.count, 2)
    }

    // MARK: Partial weeks

    func testCurrentWeekIsMarkedPartial() {
        let today = TestSupport.date(2026, 8, 12, hour: 9, calendar: calendar)
        let weeks = breakdown([transaction(10, on: today)])

        XCTAssertTrue(weeks[0].isPartial, "The week containing `now` is still running")
    }

    func testWeekClippedByTheStartOfTheRangeIsPartial() {
        // The month range starts 1 August 2026, a Saturday — so the week
        // containing it began 26 July and is cut off.
        let firstOfMonth = TestSupport.date(2026, 8, 1, calendar: calendar)

        let weeks = AnalysisAggregates.weekBreakdown(
            [transaction(10, on: firstOfMonth)],
            range: .month, now: now, calendar: calendar
        )

        XCTAssertEqual(weeks.count, 1)
        XCTAssertTrue(weeks[0].isPartial)
    }

    func testCompletedPastWeekIsNotPartial() {
        let lastWeek = TestSupport.date(2026, 8, 4, calendar: calendar)
        let weeks = breakdown([transaction(10, on: lastWeek)])

        XCTAssertFalse(weeks[0].isPartial)
    }

    // MARK: Change

    func testChangeComparesLeakAgainstTheWeekBefore() {
        let earlier = TestSupport.date(2026, 7, 28, calendar: calendar)   // week of 26 Jul
        let later = TestSupport.date(2026, 8, 4, calendar: calendar)      // week of 2 Aug

        let weeks = breakdown([
            transaction(100, on: earlier, verdict: .leak),
            transaction(150, on: later, verdict: .leak),
        ])

        let newest = weeks[0]
        XCTAssertEqual(newest.change ?? 0, 0.5, accuracy: 0.001, "150 is 50% above 100")
    }

    func testOldestWeekHasNoChange() {
        let earlier = TestSupport.date(2026, 7, 28, calendar: calendar)
        let later = TestSupport.date(2026, 8, 4, calendar: calendar)

        let weeks = breakdown([
            transaction(100, on: earlier, verdict: .leak),
            transaction(150, on: later, verdict: .leak),
        ])

        XCTAssertNil(weeks.last?.change, "Nothing to compare the first week against")
    }

    func testPartialWeekHasNoChange() {
        let lastWeek = TestSupport.date(2026, 8, 4, calendar: calendar)
        let thisWeek = TestSupport.date(2026, 8, 11, calendar: calendar)

        let weeks = breakdown([
            transaction(100, on: lastWeek, verdict: .leak),
            transaction(10, on: thisWeek, verdict: .leak),
        ])

        // Two days of this week against seven of last always looks like a
        // triumph. Saying so would be flattery, not information.
        XCTAssertTrue(weeks[0].isPartial)
        XCTAssertNil(weeks[0].change)
    }

    func testNonAdjacentWeeksAreNotCompared() {
        let old = TestSupport.date(2026, 7, 7, calendar: calendar)
        let recent = TestSupport.date(2026, 8, 4, calendar: calendar)

        let weeks = breakdown([
            transaction(100, on: old, verdict: .leak),
            transaction(150, on: recent, verdict: .leak),
        ])

        XCTAssertNil(
            weeks[0].change,
            "A month-old week isn't 'the week before', whatever its array index says"
        )
    }

    func testNoChangeWhenPreviousWeekLeakedNothing() {
        let earlier = TestSupport.date(2026, 7, 28, calendar: calendar)
        let later = TestSupport.date(2026, 8, 4, calendar: calendar)

        let weeks = breakdown([
            transaction(100, on: earlier, verdict: .worthIt),
            transaction(150, on: later, verdict: .leak),
        ])

        XCTAssertNil(weeks[0].change, "Dividing by zero is an infinity, not an insight")
    }

    // MARK: Limit and order

    func testReturnsNewestWeeksFirstAndRespectsLimit() {
        var transactions: [Transaction] = []
        for week in 0..<10 {
            let day = calendar.date(byAdding: .day, value: -7 * week, to: now)!
            transactions.append(transaction(10, on: day))
        }

        let weeks = breakdown(transactions, limit: 4)

        XCTAssertEqual(weeks.count, 4)
        XCTAssertTrue(
            zip(weeks, weeks.dropFirst()).allSatisfy { $0.start > $1.start },
            "Newest first"
        )
    }

    // MARK: Labels

    /// Builds a week covering exactly `start` through `start + 6`.
    private func whole(_ start: Date) -> AnalysisAggregates.WeekTotal {
        AnalysisAggregates.WeekTotal(
            start: start,
            coveredStart: start,
            coveredEnd: calendar.date(byAdding: .day, value: 6, to: start)!,
            spent: 0, leaked: 0, count: 0,
            isPartial: false, isCurrent: false, change: nil
        )
    }

    func testLabelCollapsesTheMonthWithinOneMonth() {
        let label = whole(TestSupport.date(2026, 8, 2, calendar: calendar)).label(calendar)
        XCTAssertTrue(label.contains("–"))
        XCTAssertEqual(label.components(separatedBy: "Aug").count - 1, 1)
    }

    func testLabelRepeatsTheMonthAcrossABoundary() {
        let label = whole(TestSupport.date(2026, 8, 30, calendar: calendar)).label(calendar)
        XCTAssertTrue(label.contains("Aug"))
        XCTAssertTrue(label.contains("Sep"))
    }

    func testLabelIsASingleDateWhenOnlyOneDayIsInRange() {
        let start = TestSupport.date(2026, 7, 26, calendar: calendar)
        let onlyDay = TestSupport.date(2026, 8, 1, calendar: calendar)
        let week = AnalysisAggregates.WeekTotal(
            start: start, coveredStart: onlyDay, coveredEnd: onlyDay,
            spent: 0, leaked: 0, count: 0,
            isPartial: true, isCurrent: false, change: nil
        )
        XCTAssertFalse(
            week.label(calendar).contains("–"),
            "Naming six days the numbers don't cover is a claim, not a label"
        )
        XCTAssertTrue(week.label(calendar).contains("Aug"))
    }

    // MARK: Coverage

    func testWeekClippedByRangeStartCoversOnlyTheDaysInRange() {
        let firstOfMonth = TestSupport.date(2026, 8, 1, calendar: calendar)

        let weeks = AnalysisAggregates.weekBreakdown(
            [transaction(10, on: firstOfMonth)],
            range: .month, now: now, calendar: calendar
        )

        let week = weeks[0]
        XCTAssertTrue(calendar.isDate(week.coveredStart, inSameDayAs: firstOfMonth))
        XCTAssertTrue(calendar.isDate(week.coveredEnd, inSameDayAs: firstOfMonth))
        XCTAssertFalse(week.isCurrent, "August 1st is not this week")
    }

    func testCompleteWeekCoversSundayThroughSaturday() {
        let midweek = TestSupport.date(2026, 8, 5, calendar: calendar)
        let week = breakdown([transaction(10, on: midweek)])[0]

        XCTAssertTrue(
            calendar.isDate(week.coveredStart,
                            inSameDayAs: TestSupport.date(2026, 8, 2, calendar: calendar))
        )
        XCTAssertTrue(
            calendar.isDate(week.coveredEnd,
                            inSameDayAs: TestSupport.date(2026, 8, 8, calendar: calendar)),
            "The exclusive end is Aug 9 00:00; the last covered day is Aug 8"
        )
    }

    func testCurrentWeekCoversUpToTodayOnly() {
        let today = TestSupport.date(2026, 8, 12, hour: 9, calendar: calendar)
        let week = breakdown([transaction(10, on: today)])[0]

        XCTAssertTrue(week.isCurrent)
        XCTAssertTrue(calendar.isDate(week.coveredEnd, inSameDayAs: today))
    }

    func testOnlyTheRunningWeekIsCurrent() {
        let lastWeek = TestSupport.date(2026, 8, 4, calendar: calendar)
        let thisWeek = TestSupport.date(2026, 8, 11, calendar: calendar)

        let weeks = breakdown([
            transaction(10, on: lastWeek),
            transaction(10, on: thisWeek),
        ])

        XCTAssertTrue(weeks[0].isCurrent)
        XCTAssertFalse(weeks[1].isCurrent)
        XCTAssertTrue(weeks[1].isPartial == false, "A finished week isn't partial")
    }

    // MARK: Note

    private func week(_ leaked: Double, start: Date, partial: Bool = false)
        -> AnalysisAggregates.WeekTotal {
        AnalysisAggregates.WeekTotal(
            start: start,
            coveredStart: start,
            coveredEnd: calendar.date(byAdding: .day, value: 6, to: start)!,
            spent: leaked * 2, leaked: leaked,
            count: 5, isPartial: partial, isCurrent: false, change: nil
        )
    }

    func testNoteStaysSilentBelowThreeWholeWeeks() {
        let weeks = [
            week(200, start: TestSupport.date(2026, 8, 2, calendar: calendar)),
            week(20, start: TestSupport.date(2026, 7, 26, calendar: calendar)),
        ]
        XCTAssertNil(AnalysisAggregates.weeklyNote(weeks, calendar: calendar))
    }

    func testNoteStaysSilentWhenNoWeekStandsOut() {
        let weeks = (0..<4).map {
            week(100, start: calendar.date(byAdding: .day, value: -7 * $0, to: now)!)
        }
        XCTAssertNil(
            AnalysisAggregates.weeklyNote(weeks, calendar: calendar),
            "Four identical weeks contain no observation worth making"
        )
    }

    func testNoteNamesAClearlyWorstWeek() {
        var weeks = (1..<4).map {
            week(50, start: calendar.date(byAdding: .day, value: -7 * $0, to: now)!)
        }
        weeks.insert(week(200, start: TestSupport.date(2026, 8, 2, calendar: calendar)), at: 0)

        let note = AnalysisAggregates.weeklyNote(weeks, calendar: calendar)
        XCTAssertNotNil(note)
        XCTAssertTrue(note?.contains("Aug 2") ?? false)
    }

    func testNoteIgnoresPartialWeeks() {
        var weeks = (1..<4).map {
            week(50, start: calendar.date(byAdding: .day, value: -7 * $0, to: now)!)
        }
        // A huge partial week shouldn't be crowned — it isn't finished, and
        // three whole weeks are still the floor for saying anything.
        weeks.insert(
            week(500, start: TestSupport.date(2026, 8, 9, calendar: calendar), partial: true),
            at: 0
        )

        let note = AnalysisAggregates.weeklyNote(weeks, calendar: calendar)
        XCTAssertNil(note)
    }
}
