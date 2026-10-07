import Foundation

/// The figures behind Overview's month picker (D-040): one cell per month,
/// grouped by year, newest year first.
///
/// Each cell carries what was spent and the share that leaked. The share — a
/// ratio, never an amount (D-020) — is what makes a month worth opening, so a
/// big rent month doesn't look like a bad one.
enum MonthGrid {

    struct Cell: Identifiable, Equatable {
        let month: Date
        let spent: Double
        let leaked: Double
        /// Inside the span Overview can show. Months before the first
        /// purchase, and after this one, can't be opened.
        let isAvailable: Bool

        var id: Date { month }
        var leakShare: Double { spent > 0 ? leaked / spent : 0 }
    }

    struct Year: Identifiable, Equatable {
        let year: Int
        let cells: [Cell]
        var id: Int { year }
    }

    static func years(
        _ transactions: [Transaction],
        available: [Date],
        calendar: Calendar = .current
    ) -> [Year] {
        let counted = transactions.filter(\.countsTowardTotals)

        var spent: [Date: Double] = [:]
        var leaked: [Date: Double] = [:]
        for t in counted {
            let month = MonthNavigator.startOfMonth(t.date, calendar: calendar)
            spent[month, default: 0] += t.amount
            if t.verdict == .leak { leaked[month, default: 0] += t.amount }
        }

        let availableSet = Set(available.map { MonthNavigator.startOfMonth($0, calendar: calendar) })
        let yearNumbers = Set(availableSet.map { calendar.component(.year, from: $0) })

        return yearNumbers.sorted(by: >).map { year in
            let cells: [Cell] = (1...12).compactMap { monthNumber in
                guard let month = calendar.date(from: DateComponents(year: year, month: monthNumber, day: 1))
                else { return nil }
                return Cell(
                    month: month,
                    spent: spent[month] ?? 0,
                    leaked: leaked[month] ?? 0,
                    isAvailable: availableSet.contains(month)
                )
            }
            return Year(year: year, cells: cells)
        }
    }
}
