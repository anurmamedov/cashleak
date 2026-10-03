import Foundation

/// The optional monthly take-home figure, and when it's worth a sentence
/// (D-030).
///
/// One number, typed once. Left at zero, none of this runs and the app is
/// exactly as it was. When it's set, it's used sparingly on purpose: a line
/// that appears on every screen every day stops being read. So each screen
/// gets at most one sentence, only when something happened, and a quiet
/// number the rest of the time.
///
/// It's also honest about its limits. CashLeak only knows the purchases it
/// captured or was told about, so the share can read lower than reality —
/// nothing here ever says "left" or "not spent", which would read like money
/// in the bank.
enum TakeHome {

    /// No sentences before this many sorted purchases this month…
    static let minimumSorted = 5
    /// …or before this day of the month, when a pace means little.
    static let minimumDay = 7

    static func share(_ amount: Double, of takeHome: Double) -> Double {
        takeHome > 0 ? amount / takeHome : 0
    }

    /// How many days of take-home an amount is — take-home over 30.
    static func days(_ amount: Double, of takeHome: Double) -> Double {
        takeHome > 0 ? amount / (takeHome / 30) : 0
    }

    /// "a day", "3 days", "about 2 weeks".
    static func daysPhrase(_ days: Double) -> String {
        let whole = Int(days.rounded())
        if whole <= 1 { return "a day" }
        if whole < 14 { return "\(whole) days" }
        let weeks = Int((days / 7).rounded())
        return weeks == 1 ? "about a week" : "about \(weeks) weeks"
    }

    static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    // MARK: Overview

    struct OverviewLine: Equatable {
        /// The small number shown whenever take-home is set.
        let label: String
        /// The one sentence, when something is worth saying. Replaces the label.
        let sentence: String?
        /// Spent as a share of take-home, for the thin bar. Capped at 1.
        let barShare: Double
    }

    /// What the Overview month card says about take-home, if anything.
    ///
    /// Priority, highest first — only one ever shows:
    /// 1. Over take-home.
    /// 2. On pace for 95% or more (current month only).
    /// 3. Leaks worth at least a day of take-home — only with no goal set,
    ///    because the goal's trade-off line already says what leaks cost.
    /// Otherwise just the number.
    static func overview(
        summary: SpendingSummary,
        takeHome: Double,
        isCurrentMonth: Bool,
        hasGoal: Bool,
        monthName: String,
        dayOfMonth: Int
    ) -> OverviewLine? {
        guard takeHome > 0, summary.spent > 0 else { return nil }

        let spentShare = share(summary.spent, of: takeHome)
        let label = isCurrentMonth
            ? "\(percent(spentShare)) of take-home so far"
            : "\(percent(spentShare)) of take-home"
        let bar = min(spentShare, 1)

        let enoughData = summary.transactionCount >= minimumSorted
            && (!isCurrentMonth || dayOfMonth >= minimumDay)
        guard enoughData else {
            return OverviewLine(label: label, sentence: nil, barShare: bar)
        }

        let when = isCurrentMonth ? "this month" : "in \(monthName)"

        if summary.spent > takeHome {
            let over = summary.spent - takeHome
            return OverviewLine(label: label, sentence: "\(over.currencyRounded) over your take-home \(when).", barShare: bar)
        }

        if isCurrentMonth, share(summary.pace, of: takeHome) >= 0.95 {
            return OverviewLine(
                label: label,
                sentence: "On pace for \(percent(share(summary.pace, of: takeHome))) of your take-home.",
                barShare: bar
            )
        }

        let leakDays = days(summary.leaked, of: takeHome)
        if !hasGoal, leakDays >= 1 {
            return OverviewLine(
                label: label,
                sentence: "\(summary.leaked.currencyRounded) leaked — \(daysPhrase(leakDays)) of take-home.",
                barShare: bar
            )
        }

        return OverviewLine(label: label, sentence: nil, barShare: bar)
    }

    // MARK: Analysis

    /// "43% of take-home" for the headline — the month's share, or the average
    /// monthly share over the months that had spending.
    static func headlineShare(
        spent: Double,
        monthsWithSpending: Int,
        takeHome: Double
    ) -> String? {
        guard takeHome > 0, spent > 0, monthsWithSpending > 0 else { return nil }
        return "\(percent(spent / (takeHome * Double(monthsWithSpending)))) of take-home"
    }

    /// At most one take-home finding for a period, or none.
    ///
    /// Priority: every month over; this year's leaks in weeks (Year only);
    /// one month standing out; every month under. Monthly bars only — weeks
    /// against a monthly figure would be guesswork.
    static func finding(
        monthBars: [AnalysisSummary.Bar],
        leaked: Double,
        sortedCount: Int,
        isYear: Bool,
        takeHome: Double
    ) -> String? {
        guard takeHome > 0, sortedCount >= minimumSorted else { return nil }

        let months = monthBars.filter { $0.spent > 0 }
        let shares = months.map { share($0.spent, of: takeHome) }

        if months.count >= 2, shares.allSatisfy({ $0 > 1 }) {
            return "You spent more than your take-home in all \(months.count) months."
        }

        if isYear {
            let leakDays = days(leaked, of: takeHome)
            if leakDays >= 7 {
                return "This year's leaks add up to \(daysPhrase(leakDays)) of take-home."
            }
        }

        if months.count >= 2, let top = zip(months, shares).max(by: { $0.1 < $1.1 }) {
            let average = shares.reduce(0, +) / Double(shares.count)
            if top.1 >= average + 0.15 {
                let name = top.0.start.formatted(.dateTime.month(.wide))
                return "\(name) was your highest share: \(percent(top.1)) of take-home."
            }
        }

        if months.count >= 2, shares.allSatisfy({ $0 < 1 }) {
            return "You spent less than your take-home in all \(months.count) months."
        }

        return nil
    }
}
