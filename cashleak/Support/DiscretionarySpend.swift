import Foundation

/// The user's own daily discretionary spend — the number that makes trip
/// forecasts personal instead of generic.
///
/// A budget calculator asserts "$80/day for food". This says "you average $34".
/// That difference is the entire feature.
enum DiscretionarySpend {

    /// Categories excluded from the daily rate.
    ///
    /// Rent doesn't travel with you, and neither does car insurance. Including
    /// them would inflate the daily figure by a factor of three and make every
    /// forecast useless.
    static let excludedCategories: Set<String> = [
        "Rent", "Utilities", "Insurance", "Phone", "Subscriptions",
    ]

    /// Mean daily discretionary spend over the trailing window.
    ///
    /// Returns `nil` rather than zero when there isn't enough history — a
    /// forecast built on four days of data would be confidently wrong, and
    /// showing nothing is more honest than showing a bad number.
    static func dailyAverage(
        from transactions: [Transaction],
        days: Int = 90,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Double? {

        guard let start = calendar.date(byAdding: .day, value: -days, to: now) else { return nil }

        let discretionary = transactions.filter {
            $0.countsTowardTotals
                && $0.date >= start
                && !excludedCategories.contains($0.category?.name ?? "")
        }

        guard discretionary.count >= 20 else { return nil }

        // Divide by the span actually covered, not the requested window — a
        // user two weeks in shouldn't have their average diluted by 76 empty
        // days.
        let earliest = discretionary.map(\.date).min() ?? start
        let span = max((calendar.dateComponents([.day], from: earliest, to: now).day ?? 1), 1)

        let total = discretionary.reduce(0) { $0 + $1.amount }
        return total / Double(span)
    }

    /// What to show when there isn't enough history yet.
    static let fallbackDaily: Double = 45
}
