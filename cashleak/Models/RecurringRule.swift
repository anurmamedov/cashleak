import Foundation
import SwiftData

/// A template that posts a transaction on a schedule.
///
/// Covers the pre-authorised debits, subscriptions, and bills that no capture
/// path can see — roughly 40–60% of typical total spend.
///
/// Posted transactions arrive **unconfirmed** like everything else. A rule is a
/// prediction, not an observation.
@Model
final class RecurringRule {

    var merchant: String = ""
    var amount: Double = 0
    var cadenceRaw: String = Cadence.monthly.rawValue

    var nextRunDate: Date = Date.distantPast

    /// `nil` until the rule has posted at least once.
    var lastPostedDate: Date?

    var isEnabled: Bool = true

    var category: Category?

    /// The day of the month the bill is really due — 31 for rent on the 31st.
    ///
    /// Each date used to be worked out from the one before, so a bill on the
    /// 31st landed on the 28th in February and then stayed on the 28th for
    /// good. Remembering the intended day lets March go back to the 31st.
    /// `0` for rules saved before this existed; filled in on the next post.
    var anchorDay: Int = 0

    var cadence: Cadence {
        get { Cadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }

    init(
        merchant: String,
        amount: Double,
        cadence: Cadence = .monthly,
        nextRunDate: Date,
        category: Category? = nil,
        isEnabled: Bool = true
    ) {
        self.merchant = merchant
        self.amount = amount
        self.cadenceRaw = cadence.rawValue
        self.nextRunDate = nextRunDate
        self.category = category
        self.isEnabled = isEnabled
        self.anchorDay = Calendar.current.component(.day, from: nextRunDate)
    }

    // MARK: Scheduling

    /// The next date after `date`, clamped to the end of shorter months.
    ///
    /// A rule anchored on the 31st posts on the 30th in April and the 28th in
    /// February, then returns to the 31st. `Calendar` clamps one step on its
    /// own; going *back* to the 31st needs `anchorDay`.
    func dateAfter(_ date: Date, calendar: Calendar = .current) -> Date {
        let step = cadence.step
        guard let next = calendar.date(byAdding: step.component, value: step.value, to: date) else {
            return date
        }

        // Weekly and biweekly count days; nothing to restore.
        guard step.component == .month || step.component == .year, anchorDay > 0 else {
            return next
        }

        // Back to the intended day, clamped to the length of this month:
        // Jan 31 → Feb 28 → Mar 31, not Mar 28.
        guard let length = calendar.range(of: .day, in: .month, for: next)?.count else { return next }
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: next)
        parts.day = min(anchorDay, length)
        return calendar.date(from: parts) ?? next
    }

    /// Advances `nextRunDate` past `now`, returning every date that should have
    /// posted.
    ///
    /// A rule that hasn't run in three months backfills three transactions —
    /// one per missed period — rather than one or twelve.
    func datesDue(asOf now: Date = .now, calendar: Calendar = .current) -> [Date] {
        guard isEnabled else { return [] }
        var due: [Date] = []
        var cursor = nextRunDate

        // Guard against a malformed rule spinning forever.
        var iterations = 0
        while cursor <= now && iterations < 512 {
            due.append(cursor)
            cursor = dateAfter(cursor, calendar: calendar)
            iterations += 1
        }
        return due
    }
}
