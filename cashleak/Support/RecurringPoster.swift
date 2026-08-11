import Foundation
import SwiftData

/// Posts recurring rules that have come due.
///
/// Rent, insurance, subscriptions and phone bills are large, predictable, and
/// invisible to every capture path — pre-authorised debits never touch Apple
/// Pay. They're also most of the money. A user whose rent is missing sees a
/// month that looks nothing like their life.
///
/// Posted transactions arrive **unconfirmed** like everything else. A rule is a
/// prediction: the amount may have changed, the charge may not have landed. The
/// user confirming it in Sort is what makes it real.
enum RecurringPoster {

    struct Outcome: Equatable {
        var posted = 0
        var deduplicated = 0
        var rejected = 0

        var total: Int { posted + deduplicated + rejected }
    }

    /// Posts everything due, advancing each rule past `now`.
    ///
    /// Safe to call repeatedly — a rule's `nextRunDate` moves past `now` before
    /// the function returns, so a second call in the same session posts nothing.
    /// That matters because this runs on launch, on foreground, and from a
    /// background refresh task, all of which can fire close together.
    @MainActor
    @discardableResult
    static func postDue(
        asOf now: Date = .now,
        calendar: Calendar = .current,
        in context: ModelContext
    ) -> Outcome {

        let descriptor = FetchDescriptor<RecurringRule>(
            predicate: #Predicate { $0.isEnabled }
        )
        guard let rules = try? context.fetch(descriptor) else { return Outcome() }

        var outcome = Outcome()

        for rule in rules {
            let due = rule.datesDue(asOf: now, calendar: calendar)
            guard !due.isEmpty else { continue }

            for date in due {
                let result = TransactionIngest.ingest(
                    amount: rule.amount,
                    merchant: rule.merchant,
                    date: date,
                    source: .recurring,
                    into: context
                )

                switch result {
                case .inserted:
                    outcome.posted += 1
                    // Recurring rules carry a category the user already chose;
                    // ingest doesn't know about it, so attach it here. This is
                    // the one source where a category is known before sorting.
                    if let category = rule.category,
                       let posted = mostRecent(matching: rule, at: date, in: context) {
                        posted.category = category
                    }
                case .duplicate:
                    // The charge was already captured another way — a
                    // subscription billed to a card that fires the Wallet
                    // trigger, for instance. Dedup did its job.
                    outcome.deduplicated += 1
                case .rejected:
                    outcome.rejected += 1
                }
            }

            rule.lastPostedDate = due.last
            rule.nextRunDate = rule.dateAfter(due.last ?? rule.nextRunDate, calendar: calendar)
        }

        try? context.save()
        return outcome
    }

    /// Finds the transaction just written for a rule, so its category can be
    /// attached. Matching on merchant and exact date is enough — it was created
    /// microseconds ago with both values set from the rule.
    @MainActor
    private static func mostRecent(
        matching rule: RecurringRule,
        at date: Date,
        in context: ModelContext
    ) -> Transaction? {
        let merchant = rule.merchant
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.merchant == merchant && $0.date == date }
        )
        return try? context.fetch(descriptor).first
    }

    /// Common Canadian recurring charges, offered during setup so the first
    /// rule takes one tap instead of five fields.
    static let templates: [(merchant: String, amount: Double, cadence: Cadence, category: String)] = [
        ("Rent",        0,     .monthly, "Rent"),
        ("Hydro",       0,     .monthly, "Utilities"),
        ("Internet",    0,     .monthly, "Utilities"),
        ("Phone",       0,     .monthly, "Phone"),
        ("Car insurance", 0,   .monthly, "Insurance"),
        ("Tenant insurance", 0, .monthly, "Insurance"),
        ("Spotify",     11.99, .monthly, "Subscriptions"),
        ("Netflix",     20.99, .monthly, "Subscriptions"),
        ("iCloud",      3.99,  .monthly, "Subscriptions"),
        ("Gym",         0,     .monthly, "Health"),
        ("Transit pass", 0,    .monthly, "Transit"),
    ]
}
