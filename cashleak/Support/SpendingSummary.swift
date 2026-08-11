import Foundation

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
