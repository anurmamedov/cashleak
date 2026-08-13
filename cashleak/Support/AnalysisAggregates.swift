import Foundation

/// Pure aggregation over transactions, kept out of the view so it can be
/// tested. Every figure on Analysis comes from here.
enum AnalysisAggregates {

    // MARK: Range

    enum Range: String, CaseIterable, Identifiable {
        case month, quarter, year

        var id: String { rawValue }

        var title: String {
            switch self {
            case .month: "Month"
            case .quarter: "3M"
            case .year: "Year"
            }
        }

        /// How the trend is bucketed. A year of daily bars is unreadable.
        var bucket: Calendar.Component {
            switch self {
            case .month: .day
            case .quarter, .year: .month
            }
        }

        func interval(endingAt now: Date = .now, calendar: Calendar = .current) -> DateInterval {
            switch self {
            case .month:
                return calendar.dateInterval(of: .month, for: now)
                    ?? DateInterval(start: now, duration: 0)
            case .quarter:
                let start = calendar.date(byAdding: .month, value: -2, to: now) ?? now
                let from = calendar.dateInterval(of: .month, for: start)?.start ?? start
                return DateInterval(start: from, end: now)
            case .year:
                let start = calendar.date(byAdding: .month, value: -11, to: now) ?? now
                let from = calendar.dateInterval(of: .month, for: start)?.start ?? start
                return DateInterval(start: from, end: now)
            }
        }
    }

    // MARK: Buckets

    struct TrendPoint: Identifiable {
        let date: Date
        let spent: Double
        let leaked: Double
        var id: Date { date }

        var kept: Double { max(spent - leaked, 0) }
    }

    struct MerchantTotal: Identifiable {
        let merchant: String
        let leaked: Double
        let count: Int
        var id: String { merchant }
    }

    struct CategoryTotal: Identifiable {
        let name: String
        let colorHex: String
        let leaked: Double
        var id: String { name }
    }

    struct WeekdayTotal: Identifiable {
        /// 1 = Sunday, matching `Calendar.component(.weekday:)`.
        let weekday: Int
        let spent: Double
        let leaked: Double
        var id: Int { weekday }

        var shortName: String {
            let symbols = Calendar.current.veryShortWeekdaySymbols
            return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "?"
        }

        var fullName: String {
            let symbols = Calendar.current.weekdaySymbols
            return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "?"
        }

        /// Spend per occurrence of this weekday in the range.
        ///
        /// A raw total says more about how many Mondays fell inside the range
        /// than about Mondays.
        func averagePerOccurrence(_ occurrences: [Int: Int]) -> Double {
            let count = occurrences[weekday] ?? 0
            return count > 0 ? spent / Double(count) : 0
        }

        var leakShare: Double {
            spent > 0 ? leaked / spent : 0
        }
    }

    /// How many times each weekday actually falls inside the range.
    static func weekdayOccurrences(
        in range: Range,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Int: Int] {

        let interval = range.interval(endingAt: now, calendar: calendar)
        var counts: [Int: Int] = [:]
        var cursor = calendar.startOfDay(for: interval.start)
        let end = min(interval.end, now)

        var guardCount = 0
        while cursor <= end && guardCount < 400 {
            let weekday = calendar.component(.weekday, from: cursor)
            counts[weekday, default: 0] += 1
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end.addingTimeInterval(1)
            guardCount += 1
        }
        return counts
    }

    // MARK: Week over week

    struct WeekComparison: Equatable {
        let thisWeekRatio: Double
        let lastWeekRatio: Double
        let thisWeekLeaked: Double
        let lastWeekLeaked: Double

        /// Negative means improvement — less of what you'd take back.
        var change: Double { thisWeekRatio - lastWeekRatio }
        var isImprovement: Bool { change < 0 }

        /// Percentage points, not a percentage of a percentage.
        var pointsChanged: Int { Int((abs(change) * 100).rounded()) }
    }

    /// This week against last week.
    ///
    /// The month figure blends them, which hides exactly the thing the product
    /// exists to reward. Someone who halved their leak mid-month sees an
    /// unremarkable average and no reason to keep going.
    ///
    /// Returns `nil` unless both weeks have enough data to compare honestly.
    static func weekOverWeek(
        _ transactions: [Transaction],
        now: Date = .now,
        calendar: Calendar = .current,
        minimumPerWeek: Int = 5
    ) -> WeekComparison? {

        guard
            let thisWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
            let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: thisWeekStart)
        else { return nil }

        let counted = transactions.filter(\.countsTowardTotals)

        let thisWeek = counted.filter { $0.date >= thisWeekStart && $0.date <= now }
        let lastWeek = counted.filter { $0.date >= lastWeekStart && $0.date < thisWeekStart }

        guard thisWeek.count >= minimumPerWeek, lastWeek.count >= minimumPerWeek else {
            return nil
        }

        func ratio(_ set: [Transaction]) -> (ratio: Double, leaked: Double) {
            let spent = set.reduce(0) { $0 + $1.amount }
            let leaked = set.filter { $0.verdict == .leak }.reduce(0) { $0 + $1.amount }
            return (spent > 0 ? leaked / spent : 0, leaked)
        }

        let current = ratio(thisWeek)
        let previous = ratio(lastWeek)

        return WeekComparison(
            thisWeekRatio: current.ratio,
            lastWeekRatio: previous.ratio,
            thisWeekLeaked: current.leaked,
            lastWeekLeaked: previous.leaked
        )
    }

    // MARK: Filtering

    /// Confirmed, not superseded, inside the range. Everything else here builds
    /// on this — an unconfirmed record is a parser's claim, not a fact.
    static func counted(
        _ transactions: [Transaction],
        in range: Range,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Transaction] {
        let interval = range.interval(endingAt: now, calendar: calendar)
        return transactions.filter {
            $0.countsTowardTotals && $0.date >= interval.start && $0.date <= max(interval.end, now)
        }
    }

    // MARK: Trend

    static func trend(
        _ transactions: [Transaction],
        range: Range,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [TrendPoint] {

        let counted = counted(transactions, in: range, now: now, calendar: calendar)
        guard !counted.isEmpty else { return [] }

        var spent: [Date: Double] = [:]
        var leaked: [Date: Double] = [:]

        for transaction in counted {
            let key = calendar.dateInterval(of: range.bucket, for: transaction.date)?.start
                ?? transaction.date
            spent[key, default: 0] += transaction.amount
            if transaction.verdict == .leak {
                leaked[key, default: 0] += transaction.amount
            }
        }

        return spent.keys.sorted().map { key in
            TrendPoint(date: key, spent: spent[key] ?? 0, leaked: leaked[key] ?? 0)
        }
    }

    // MARK: Leaderboards

    /// Merchants ranked by how much the user regretted spending there.
    ///
    /// Ranked by leak, not by total. A grocery bill is usually the largest line
    /// on any statement and almost never the answer to "what would I take back".
    static func merchantLeaderboard(
        _ transactions: [Transaction],
        range: Range,
        limit: Int = 5,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [MerchantTotal] {

        let leaks = counted(transactions, in: range, now: now, calendar: calendar)
            .filter { $0.verdict == .leak && !$0.merchant.isEmpty }

        var totals: [String: (amount: Double, count: Int, display: String)] = [:]
        for transaction in leaks {
            let key = transaction.normalizedMerchant.isEmpty
                ? transaction.merchant.lowercased()
                : transaction.normalizedMerchant
            let existing = totals[key]
            totals[key] = (
                (existing?.amount ?? 0) + transaction.amount,
                (existing?.count ?? 0) + 1,
                existing?.display ?? transaction.merchant
            )
        }

        return totals.values
            .map { MerchantTotal(merchant: $0.display, leaked: $0.amount, count: $0.count) }
            .sorted { $0.leaked > $1.leaked }
            .prefix(limit)
            .map { $0 }
    }

    static func categoryLeaks(
        _ transactions: [Transaction],
        range: Range,
        limit: Int = 6,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [CategoryTotal] {

        let leaks = counted(transactions, in: range, now: now, calendar: calendar)
            .filter { $0.verdict == .leak }

        var totals: [String: (amount: Double, hex: String)] = [:]
        for transaction in leaks {
            let name = transaction.category?.name ?? "Uncategorised"
            let hex = transaction.category?.colorHex ?? "888780"
            totals[name] = ((totals[name]?.amount ?? 0) + transaction.amount, hex)
        }

        return totals
            .map { CategoryTotal(name: $0.key, colorHex: $0.value.hex, leaked: $0.value.amount) }
            .sorted { $0.leaked > $1.leaked }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Weekday

    /// Always returns seven entries, including zeroes.
    ///
    /// A missing bar reads as missing data; a zero bar reads as a quiet day.
    static func weekdayPattern(
        _ transactions: [Transaction],
        range: Range,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [WeekdayTotal] {

        let counted = counted(transactions, in: range, now: now, calendar: calendar)

        var spent = [Int: Double]()
        var leaked = [Int: Double]()

        for transaction in counted {
            let weekday = calendar.component(.weekday, from: transaction.date)
            spent[weekday, default: 0] += transaction.amount
            if transaction.verdict == .leak {
                leaked[weekday, default: 0] += transaction.amount
            }
        }

        return (1...7).map {
            WeekdayTotal(weekday: $0, spent: spent[$0] ?? 0, leaked: leaked[$0] ?? 0)
        }
    }

    // MARK: Finding

    /// One plain-language observation, or `nil` when there isn't enough data to
    /// say anything honest.
    ///
    /// This is the only place the app volunteers an opinion, so it has to be
    /// true and it has to be worth the words. Silence beats a weak finding.
    static func finding(
        _ transactions: [Transaction],
        range: Range,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String? {

        let counted = counted(transactions, in: range, now: now, calendar: calendar)
        guard counted.count >= 15 else { return nil }

        // Candidate 1 — the most expensive weekday, if it's meaningfully worse
        // and there's enough of each day to mean anything.
        //
        // The transaction count alone isn't enough of a gate. Over two weeks
        // there are only two Sundays, so "Sunday costs €333 more than Friday"
        // is a difference between two days and two other days, presented as a
        // pattern. Requiring at least three occurrences of each weekday pushes
        // this past a month of data, which is the point at which a weekday
        // habit is a habit rather than a coincidence.
        let occurrences = weekdayOccurrences(in: range, now: now, calendar: calendar)
        let weekdays = weekdayPattern(transactions, range: range, now: now, calendar: calendar)
            .filter { $0.spent > 0 && (occurrences[$0.weekday] ?? 0) >= 3 }

        if weekdays.count >= 5,
           let worst = weekdays.max(by: { $0.averagePerOccurrence(occurrences) < $1.averagePerOccurrence(occurrences) }),
           let best = weekdays.min(by: { $0.averagePerOccurrence(occurrences) < $1.averagePerOccurrence(occurrences) }),
           worst.weekday != best.weekday {

            // Compare per-occurrence averages, not raw totals. A total says
            // more about how many Sundays fell in the range than about Sundays.
            let worstAverage = worst.averagePerOccurrence(occurrences)
            let bestAverage = best.averagePerOccurrence(occurrences)
            let gap = worstAverage - bestAverage

            if gap > worstAverage * 0.35 {
                return "\(worst.fullName) is your most expensive day — about \(gap.currencyRounded) more than a \(best.fullName), every time."
            }
        }

        // Candidate 2 — a single merchant dominating the leak.
        let merchants = merchantLeaderboard(transactions, range: range, now: now, calendar: calendar)
        let totalLeaked = counted.filter { $0.verdict == .leak }.reduce(0) { $0 + $1.amount }

        if let top = merchants.first, totalLeaked > 0 {
            let share = top.leaked / totalLeaked
            if share > 0.3 && top.count >= 3 {
                return "\(top.merchant) is \(Int((share * 100).rounded()))% of what you'd take back — \(top.count) visits this period."
            }
        }

        // Candidate 3 — the ratio itself, stated without comment.
        let spent = counted.reduce(0) { $0 + $1.amount }
        guard spent > 0 else { return nil }
        let ratio = Int((totalLeaked / spent * 100).rounded())
        if ratio > 0 {
            return "You'd take back \(ratio)% of what you spent. The rest was worth it."
        }

        return nil
    }
}
