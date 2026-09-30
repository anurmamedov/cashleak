import Foundation
import SwiftData

/// Month-to-date aggregates.
///
/// Only confirmed, non-superseded transactions count. An unconfirmed record is
/// a claim from a parser, and letting it reach a total before a human has seen
/// it is the failure mode DECISIONS.md warns about.
struct SpendingSummary {

    let spent: Double
    let leaked: Double
    let kept: Double
    let transactionCount: Int
    let daysOfHistory: Int

    /// Leak as a share of confirmed spend. Zero when nothing is confirmed —
    /// never a division by zero, never a spurious 100%.
    var leakRatio: Double {
        spent > 0 ? leaked / spent : 0
    }

    /// Projected month-end spend from the current daily rate.
    let pace: Double

    /// Days elapsed in the month so far.
    let daysElapsed: Int

    /// Whether the projection is worth showing.
    ///
    /// Extrapolating a month from two days produces a number that's
    /// arithmetically correct and practically nonsense — one big grocery run on
    /// the 2nd projects to a catastrophic month. Below a week, the projection
    /// says more about the sample than about the user.
    var paceIsMeaningful: Bool {
        daysElapsed >= 7 && spent > 0
    }

    /// Average spend per day over the days counted.
    ///
    /// For a finished month this is the whole month, which is why a past month
    /// shows it in place of pace — projecting a month that has already ended
    /// says nothing.
    var perDay: Double {
        spent / Double(max(daysElapsed, 1))
    }

    var hasMeaningfulData: Bool {
        LeakRamp.hasMeaningfulData(
            transactionCount: transactionCount,
            daysOfHistory: daysOfHistory
        )
    }

    static let empty = SpendingSummary(
        spent: 0, leaked: 0, kept: 0,
        transactionCount: 0, daysOfHistory: 0, pace: 0, daysElapsed: 0
    )

    /// - Parameters:
    ///   - transactions: any set; filtering to confirmed happens here.
    ///   - month: the month to summarise. Defaults to now.
    static func make(
        from transactions: [Transaction],
        month: Date = .now,
        calendar: Calendar = .current
    ) -> SpendingSummary {

        guard let interval = calendar.dateInterval(of: .month, for: month) else { return .empty }

        let counted = transactions.filter {
            $0.countsTowardTotals && interval.contains($0.date)
        }

        guard !counted.isEmpty else { return .empty }

        let spent = counted.reduce(0) { $0 + $1.amount }
        let leaked = counted.filter { $0.verdict == .leak }.reduce(0) { $0 + $1.amount }
        let kept = counted.filter { $0.verdict == .worthIt }.reduce(0) { $0 + $1.amount }

        let earliest = counted.map(\.date).min() ?? interval.start
        let daysOfHistory = (calendar.dateComponents([.day], from: earliest, to: .now).day ?? 0) + 1

        // Pace: daily rate so far, projected across the whole month.
        let elapsed = max((calendar.dateComponents([.day], from: interval.start, to: min(.now, interval.end)).day ?? 0), 1)
        let daysInMonth = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let pace = (spent / Double(elapsed)) * Double(daysInMonth)

        return SpendingSummary(
            spent: spent,
            leaked: leaked,
            kept: kept,
            transactionCount: counted.count,
            daysOfHistory: daysOfHistory,
            pace: pace,
            daysElapsed: elapsed
        )
    }

    /// All spending in one category for a month, with the part that leaked.
    struct CategorySpend: Identifiable {
        let category: Category?
        let total: Double
        let leaked: Double
        let count: Int

        var name: String { category?.name ?? "Uncategorised" }
        /// The category's own identity, not its name — two categories can share
        /// a name, and a list keyed on it would merge their rows on screen.
        var id: PersistentIdentifier? { category?.persistentModelID }
    }

    /// Every category's spending for the month, largest first — not just
    /// leaks.
    ///
    /// Overview used to list leaks only, so anything marked worth it vanished
    /// from the screen: fourteen coffees you were happy with appeared nowhere.
    /// This answers "where did my money go", with the leaked share carried
    /// alongside so the verdict is still visible inside each row.
    static func byCategory(
        from transactions: [Transaction],
        month: Date = .now,
        calendar: Calendar = .current
    ) -> [CategorySpend] {

        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }

        let counted = transactions.filter {
            $0.countsTowardTotals && interval.contains($0.date)
        }

        var totals: [Category?: (total: Double, leaked: Double, count: Int)] = [:]
        for t in counted {
            var entry = totals[t.category, default: (0, 0, 0)]
            entry.total += t.amount
            if t.verdict == .leak { entry.leaked += t.amount }
            entry.count += 1
            totals[t.category] = entry
        }

        return totals
            .map { CategorySpend(category: $0.key, total: $0.value.total, leaked: $0.value.leaked, count: $0.value.count) }
            .sorted { $0.total == $1.total ? $0.name < $1.name : $0.total > $1.total }
    }

    /// Purchases on one calendar day, newest first — sorted or not.
    ///
    /// Includes captures still waiting in Sort. The question this answers is
    /// "did my coffee register?", and hiding an unsorted one would answer it
    /// wrongly. Totals are separate; this is a list of what happened.
    static func purchases(
        on day: Date,
        from transactions: [Transaction],
        calendar: Calendar = .current
    ) -> [Transaction] {
        transactions
            .filter { !$0.isSuperseded && calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date > $1.date }
    }

    /// Leak totals per category, largest first.
    static func leaksByCategory(
        from transactions: [Transaction],
        month: Date = .now,
        calendar: Calendar = .current
    ) -> [(category: Category?, total: Double)] {

        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }

        let leaks = transactions.filter {
            $0.countsTowardTotals && $0.verdict == .leak && interval.contains($0.date)
        }

        var totals: [Category?: Double] = [:]
        for t in leaks {
            totals[t.category, default: 0] += t.amount
        }

        return totals
            .map { (category: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }
}

extension Double {
    /// `$1,284` — no decimals. Amounts in this app are glanceable, not
    /// accounting figures.
    var currencyRounded: String {
        Self.format(self, fractionDigits: 0)
    }

    /// `$34.20` — used where the exact figure matters, like a queue row.
    var currencyExact: String {
        Self.format(self, fractionDigits: 2)
    }

    /// Formats in a specific currency, for a transaction captured abroad.
    func currency(code: String, fractionDigits: Int = 2) -> String {
        Self.format(self, fractionDigits: fractionDigits, code: code)
    }

    private static func format(
        _ value: Double,
        fractionDigits: Int,
        code: String = AppSettings.currencyCode
    ) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = fractionDigits
        f.maximumFractionDigits = fractionDigits
        f.currencyCode = code
        f.locale = .current
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
