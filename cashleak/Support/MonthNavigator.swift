import Foundation

/// Which months Overview can show, and how to move between them.
///
/// Pure functions over dates so the edges are testable — January going back
/// to the previous December, a first transaction on the last day of a month,
/// a user with no history at all. A month switcher that skips or repeats a
/// month renders exactly like one that works.
enum MonthNavigator {

    /// The first instant of the month containing `date`.
    static func startOfMonth(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }

    /// Every month from the earliest date's month through the current month,
    /// oldest first.
    ///
    /// Continuous, including empty months in between. Skipping a quiet month
    /// would make the arrows jump from June to August, and a user who spent
    /// nothing in July should see July say so rather than wonder where it went.
    ///
    /// Always contains the current month, so a brand-new user still has
    /// somewhere to be.
    static func availableMonths(
        from dates: [Date],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [Date] {
        let current = startOfMonth(now, calendar: calendar)
        guard let earliest = dates.min() else { return [current] }

        var month = startOfMonth(min(earliest, now), calendar: calendar)
        var months: [Date] = []

        while month <= current {
            months.append(month)
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return months.isEmpty ? [current] : months
    }

    /// The month before `month`, if there's history there.
    static func previous(
        before month: Date,
        in months: [Date],
        calendar: Calendar = .current
    ) -> Date? {
        guard let index = index(of: month, in: months, calendar: calendar), index > 0 else { return nil }
        return months[index - 1]
    }

    /// The month after `month`, never past the current one.
    static func next(
        after month: Date,
        in months: [Date],
        calendar: Calendar = .current
    ) -> Date? {
        guard let index = index(of: month, in: months, calendar: calendar),
              index < months.count - 1 else { return nil }
        return months[index + 1]
    }

    static func index(of month: Date, in months: [Date], calendar: Calendar = .current) -> Int? {
        months.firstIndex { calendar.isDate($0, equalTo: month, toGranularity: .month) }
    }

    static func isCurrent(_ month: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.isDate(month, equalTo: now, toGranularity: .month)
    }

    /// The last day of the month, for "By Sep 30 at this rate".
    static func lastDay(of month: Date, calendar: Calendar = .current) -> Date {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return month }
        return interval.end.addingTimeInterval(-1)
    }
}
