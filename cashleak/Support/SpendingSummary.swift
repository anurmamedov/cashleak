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

    var hasMeaningfulData: Bool {
        LeakRamp.hasMeaningfulData(
            transactionCount: transactionCount,
            daysOfHistory: daysOfHistory
        )
    }

    static let empty = SpendingSummary(
        spent: 0, leaked: 0, kept: 0,
        transactionCount: 0, daysOfHistory: 0, pace: 0
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
            pace: pace
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
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.currencyCode = "CAD"
        return f.string(from: NSNumber(value: self)) ?? "$0"
    }

    /// `$34.20` — used where the exact figure matters, like a queue row.
    var currencyExact: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.currencyCode = "CAD"
        return f.string(from: NSNumber(value: self)) ?? "$0.00"
    }
}
