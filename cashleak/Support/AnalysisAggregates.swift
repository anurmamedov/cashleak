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

        // Candidate 1 — the most expensive weekday, if it's meaningfully worse.
        let weekdays = weekdayPattern(transactions, range: range, now: now, calendar: calendar)
            .filter { $0.spent > 0 }

        if weekdays.count >= 5,
           let worst = weekdays.max(by: { $0.spent < $1.spent }),
           let best = weekdays.min(by: { $0.spent < $1.spent }),
           worst.weekday != best.weekday {
            let gap = worst.spent - best.spent
            if gap > worst.spent * 0.35 {
                return "\(worst.fullName) is your most expensive day. It costs about \(gap.currencyRounded) more than a \(best.fullName)."
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
