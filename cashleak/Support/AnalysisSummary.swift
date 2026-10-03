import Foundation

/// The figures behind the redesigned Analysis screen (D-023): one headline,
/// one set of bars, and findings in plain words.
///
/// Sits beside `AnalysisAggregates` rather than replacing it — the leaderboards
/// and the pattern finding there are reused as they are.
enum AnalysisSummary {

    // MARK: Headline

    struct Headline: Equatable {
        let spent: Double
        let leaked: Double
        let kept: Double
        let count: Int
        /// The line under the number: a comparison for a month, an average for
        /// longer ranges. `nil` when there's nothing honest to say.
        let context: String?
    }

    static func headline(
        _ transactions: [Transaction],
        range: AnalysisAggregates.Range,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Headline {
        let counted = AnalysisAggregates.counted(transactions, in: range, now: now, calendar: calendar)
        let spent = total(counted)
        let leaked = total(counted.filter { $0.verdict == .leak })
        let kept = total(counted.filter { $0.verdict == .worthIt })

        let context: String?
        switch range {
        case .month:
            context = monthComparison(transactions, spent: spent, now: now, calendar: calendar)
        case .quarter, .year:
            let months = bars(transactions, range: range, now: now, calendar: calendar)
                .filter { $0.spent > 0 }
            context = months.count >= 2
                ? "Average \((spent / Double(months.count)).currencyRounded) a month"
                : nil
        }

        return Headline(spent: spent, leaked: leaked, kept: kept, count: counted.count, context: context)
    }

    /// This month so far against **the same point** last month.
    ///
    /// Comparing half of September with all of August would always read as
    /// "less than August" until the 30th — true arithmetic, false impression.
    static func monthComparison(
        _ transactions: [Transaction],
        spent: Double,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String? {
        guard
            let thisMonth = calendar.dateInterval(of: .month, for: now),
            let lastMonthDate = calendar.date(byAdding: .month, value: -1, to: thisMonth.start),
            let lastMonth = calendar.dateInterval(of: .month, for: lastMonthDate)
        else { return nil }

        let elapsed = now.timeIntervalSince(thisMonth.start)
        let cutoff = min(lastMonth.start.addingTimeInterval(elapsed), lastMonth.end)

        let previous = transactions.filter {
            $0.countsTowardTotals && $0.date >= lastMonth.start && $0.date < cutoff
        }
        guard !previous.isEmpty else { return nil }

        let difference = spent - total(previous)
        let name = lastMonth.start.formatted(.dateTime.month(.wide))
        let isWholeMonth = cutoff >= lastMonth.end

        if abs(difference) < 1 {
            return isWholeMonth ? "About the same as \(name)" : "About the same as this time in \(name)"
        }
        let direction = difference > 0 ? "↑ \(difference.currencyRounded) more" : "↓ \(abs(difference).currencyRounded) less"
        return isWholeMonth ? "\(direction) than \(name)" : "\(direction) than this time in \(name)"
    }

    // MARK: Bars

    struct Bar: Identifiable, Equatable {
        let start: Date
        let end: Date
        let label: String
        let spent: Double
        let leaked: Double
        var id: Date { start }
    }

    /// Weeks for a month, months for 3 months and a year.
    ///
    /// Never days: most days are empty, and a month of daily bars is mostly
    /// blank space with one spike. Empty buckets are kept so the axis doesn't
    /// jump — a quiet month should look quiet, not missing.
    static func bars(
        _ transactions: [Transaction],
        range: AnalysisAggregates.Range,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Bar] {
        let interval = range.interval(endingAt: now, calendar: calendar)
        let counted = AnalysisAggregates.counted(transactions, in: range, now: now, calendar: calendar)

        var buckets: [(start: Date, end: Date, label: String)] = []

        switch range {
        case .month:
            var cursor = interval.start
            while cursor <= now, cursor < interval.end {
                let week = calendar.dateInterval(of: .weekOfYear, for: cursor)
                let end = min(week?.end ?? interval.end, interval.end)
                buckets.append((cursor, end, cursor.formatted(.dateTime.month(.abbreviated).day())))
                cursor = end
            }
        case .quarter, .year:
            let count = range == .quarter ? 3 : 12
            for offset in 0..<count {
                guard
                    let date = calendar.date(byAdding: .month, value: offset, to: interval.start),
                    let month = calendar.dateInterval(of: .month, for: date)
                else { continue }
                let label = range == .quarter
                    ? month.start.formatted(.dateTime.month(.abbreviated))
                    : month.start.formatted(.dateTime.month(.narrow))
                buckets.append((month.start, month.end, label))
            }
        }

        return buckets.map { bucket in
            let inside = counted.filter { $0.date >= bucket.start && $0.date < bucket.end }
            return Bar(
                start: bucket.start,
                end: bucket.end,
                label: bucket.label,
                spent: total(inside),
                leaked: total(inside.filter { $0.verdict == .leak })
            )
        }
    }

    /// The height the tallest bar is drawn at.
    ///
    /// One bar far above the rest — rent in the first week — would flatten every
    /// other bar into a line. When the biggest is more than 2.5 times the next,
    /// the scale is set by the next one and the big bar is drawn cut off, with
    /// its real amount still printed on it.
    static func chartCeiling(for bars: [Bar]) -> (ceiling: Double, isCapped: Bool) {
        let values = bars.map(\.spent).filter { $0 > 0 }.sorted(by: >)
        guard let largest = values.first else { return (1, false) }
        guard values.count >= 2 else { return (largest, false) }
        let second = values[1]
        if largest > second * 2.5 {
            return (second * 1.3, true)
        }
        return (largest, false)
    }

    // MARK: Findings

    struct Finding: Identifiable, Equatable {
        enum Kind: Equatable { case fact, pattern }
        let icon: String
        /// Markdown; `**bold**` marks the part worth reading first.
        let text: String
        let kind: Kind
        var id: String { text }
    }

    /// Patterns wait for this many sorted purchases. Facts don't. (D-023)
    static let patternThreshold = 15

    /// Plain-language findings, facts first.
    ///
    /// **Facts** are arithmetic — a comparison, the biggest week, the top
    /// category, a regular merchant — and are true from the first purchase.
    /// **Patterns** are claims about habits, and a habit read off ten purchases
    /// is mostly chance, so they wait for `patternThreshold`. A finding that's
    /// obviously wrong costs the credibility of every other one.
    static func findings(
        _ transactions: [Transaction],
        range: AnalysisAggregates.Range,
        takeHome: Double = 0,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Finding] {
        let counted = AnalysisAggregates.counted(transactions, in: range, now: now, calendar: calendar)
        guard !counted.isEmpty else { return [] }

        var result: [Finding] = []
        let unit = range == .month ? "week" : "month"

        // 1. Against last month.
        if range == .month,
           let line = monthComparison(transactions, spent: total(counted), now: now, calendar: calendar) {
            let icon = line.hasPrefix("↓") ? "arrow.down.right" : (line.hasPrefix("↑") ? "arrow.up.right" : "equal")
            var words = line
                .replacingOccurrences(of: "↑ ", with: "")
                .replacingOccurrences(of: "↓ ", with: "")
            if words.hasPrefix("About") { words = "a" + words.dropFirst() }
            result.append(Finding(icon: icon, text: "You've spent **\(words)**.", kind: .fact))
        }

        // 2. The leakiest bar.
        let allBars = bars(transactions, range: range, now: now, calendar: calendar)
        if let worst = allBars.filter({ $0.leaked > 0 }).max(by: { $0.leaked < $1.leaked }),
           allBars.filter({ $0.spent > 0 }).count >= 2 {
            let inside = counted.filter { $0.date >= worst.start && $0.date < worst.end && $0.verdict == .leak }
            let name = range == .month
                ? "The week of \(worst.label)"
                : worst.start.formatted(.dateTime.month(.wide))
            var text = "**\(name)** was your leakiest \(unit): \(worst.leaked.currencyRounded)"
            if let top = topCategory(inside), top.amount > worst.leaked * 0.5 {
                text += ", mostly \(top.name)"
            }
            result.append(Finding(icon: "flame", text: text + ".", kind: .fact))
        }

        // 3. Where most money went.
        let spent = total(counted)
        if let top = topCategory(counted), spent > 0 {
            let share = Int((top.amount / spent * 100).rounded())
            result.append(Finding(
                icon: "chart.pie",
                text: "Most money went to **\(top.name)**: \(top.amount.currencyRounded), \(share)% of the total.",
                kind: .fact
            ))
        }

        // 4. A regular.
        if let regular = mostVisited(counted), regular.count >= 3 {
            result.append(Finding(
                icon: "repeat",
                text: "**\(regular.name)**: \(regular.count) purchases, \(regular.amount.currencyRounded) in all.",
                kind: .fact
            ))
        }

        // 5. Take-home, if set — at most one, and only when it says something
        //    (D-030). Monthly bars only, so 3 months and Year.
        if range != .month,
           let line = TakeHome.finding(
               monthBars: allBars,
               leaked: total(counted.filter { $0.verdict == .leak }),
               sortedCount: counted.count,
               isYear: range == .year,
               takeHome: takeHome
           ) {
            result.append(Finding(icon: "banknote", text: line, kind: .fact))
        }

        // 6. A habit — only with enough data. Reuses the existing gated finding.
        if counted.count >= patternThreshold,
           let pattern = AnalysisAggregates.finding(transactions, range: range, now: now, calendar: calendar) {
            result.append(Finding(icon: "sparkles", text: pattern, kind: .pattern))
        }

        return result
    }

    // MARK: Helpers

    private static func total(_ transactions: [Transaction]) -> Double {
        transactions.reduce(0) { $0 + $1.amount }
    }

    private static func topCategory(_ transactions: [Transaction]) -> (name: String, amount: Double)? {
        var totals: [String: Double] = [:]
        for t in transactions {
            totals[t.category?.name ?? "Uncategorised", default: 0] += t.amount
        }
        return totals.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }
            .map { (name: $0.key, amount: $0.value) }
    }

    private static func mostVisited(_ transactions: [Transaction]) -> (name: String, count: Int, amount: Double)? {
        var visits: [String: (display: String, count: Int, amount: Double)] = [:]
        for t in transactions where !t.merchant.isEmpty {
            let key = t.normalizedMerchant.isEmpty ? t.merchant.lowercased() : t.normalizedMerchant
            let existing = visits[key]
            visits[key] = (existing?.display ?? t.merchant, (existing?.count ?? 0) + 1, (existing?.amount ?? 0) + t.amount)
        }
        return visits.values
            .max { $0.count == $1.count ? $0.amount < $1.amount : $0.count < $1.count }
            .map { (name: $0.display, count: $0.count, amount: $0.amount) }
    }
}
