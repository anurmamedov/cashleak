import Foundation
import SwiftData

/// The single door every captured transaction comes through.
///
/// Wallet automation, bank alert, receipt scan, recurring rule — all of them
/// call `ingest`. Nothing writes a `Transaction` directly, which is what makes
/// two guarantees enforceable in one place rather than five:
///
/// 1. Everything enters **unconfirmed**. A capture source makes a claim; only a
///    person turns it into a fact.
/// 2. Dedup runs on **every** write, not on a nightly sweep. A duplicate that
///    reaches a total even briefly has already been seen.
enum TransactionIngest {

    enum Result: Equatable {
        /// Stored and queued for sorting.
        case inserted
        /// Matched an existing record; the weaker of the two is superseded.
        case duplicate
        /// Rejected before touching the store.
        case rejected(Reason)

        enum Reason: String, Equatable {
            case nonPositiveAmount
            case implausiblyLarge
        }
    }

    /// Above this, treat the input as a parse error rather than a purchase.
    ///
    /// A bank alert regex that grabs an account balance instead of an amount
    /// produces exactly this, and one bad parse would dominate every chart for
    /// the month.
    static let implausibleAmount: Double = 100_000

    @MainActor
    @discardableResult
    static func ingest(
        amount: Double,
        merchant: String?,
        date: Date = .now,
        source: TransactionSource,
        note: String = "",
        into context: ModelContext
    ) -> Result {

        // The Wallet trigger fires on declined transactions too. A decline has
        // no amount worth recording, and this is the cheapest place to drop it.
        guard amount > 0 else { return .rejected(.nonPositiveAmount) }
        guard amount < implausibleAmount else { return .rejected(.implausiblyLarge) }

        let cleanMerchant = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Only fetch the window that could possibly match. Scanning the whole
        // store on every tap would degrade as history grows.
        let lowerBound = date.addingTimeInterval(-DeduplicationMatcher.window)
        let upperBound = date.addingTimeInterval(DeduplicationMatcher.window)

        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= lowerBound && $0.date <= upperBound }
        )
        let nearby = (try? context.fetch(descriptor)) ?? []

        let incoming = Transaction(
            amount: amount,
            date: date,
            merchant: cleanMerchant,
            note: note,
            source: source,
            verdict: .unrated,
            isConfirmed: false
        )

        if let existing = DeduplicationMatcher.firstMatch(
            amount: amount,
            merchant: cleanMerchant,
            date: date,
            source: source,
            among: nearby
        ) {
            // Both records are kept. The weaker one is flagged, never deleted,
            // so a wrong merge is recoverable — and if the matcher is tuned
            // badly, the evidence is still in the store.
            let keeper = DeduplicationMatcher.preferred(existing, incoming)

            context.insert(incoming)
            if keeper === incoming {
                existing.isSuperseded = true
                // Carry forward anything the human already did.
                if incoming.category == nil { incoming.category = existing.category }
                if existing.isConfirmed {
                    incoming.isConfirmed = true
                    incoming.verdict = existing.verdict
                }
            } else {
                incoming.isSuperseded = true
                // Fill gaps in the keeper from the newcomer.
                if keeper.merchant.isEmpty && !incoming.merchant.isEmpty {
                    keeper.setMerchant(incoming.merchant)
                }
            }

            try? context.save()
            return .duplicate
        }

        applySuggestedCategory(to: incoming, in: context)

        context.insert(incoming)
        try? context.save()
        return .inserted
    }

    /// Fills in a category so the Sort queue starts from a guess rather than a
    /// blank.
    ///
    /// Sorting is the one thing the app asks of people every day, and picking
    /// the same category for the same coffee shop forty times is the friction
    /// that makes them stop. Wallet delivers clean Maps-resolved merchant names
    /// (L3), which is what makes a guess possible at all.
    ///
    /// The category only. **Never a verdict, never `isConfirmed`** — a guess
    /// about where money went is a filing convenience; a guess about whether it
    /// was worth spending is the product making the user's judgement for them.
    /// See D-002 and the verdict rule in CLAUDE.md.
    ///
    /// The user's own history outranks the table, so one correction sticks.
    @MainActor
    private static func applySuggestedCategory(
        to transaction: Transaction,
        in context: ModelContext
    ) {
        guard transaction.category == nil, !transaction.merchant.isEmpty else { return }

        if let remembered = MerchantMemory.lastCategory(
            forMerchant: transaction.merchant, in: context
        ) {
            transaction.category = remembered
            return
        }

        guard let name = MerchantCategoryHints.categoryName(forMerchant: transaction.merchant)
        else { return }

        // Match the user's own categories by name. A renamed or deleted
        // category simply yields no suggestion — the table never creates one,
        // because inventing categories nobody asked for is how a tidy list
        // turns into a mess.
        let descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.name == name }
        )
        transaction.category = (try? context.fetch(descriptor))?.first
    }
}
