import Foundation
import SwiftData

/// The single door every captured transaction comes through.
///
/// Wallet automation, bank alert, receipt scan, recurring rule — all of them
/// call `ingest`. Nothing writes a `Transaction` directly, which is what makes
/// two guarantees enforceable in one place rather than five:
///
/// 1. Everything a **capture source** sends enters unconfirmed. A source makes
///    a claim; only a person turns it into a fact. The one exception is a
///    record a person entered or checked themselves on the Add sheet (D-034) —
///    passed as `personVerdict`, honoured for `.manual` and `.scan` only.
/// 2. Dedup runs on **every** write, not on a nightly sweep. A duplicate that
///    reaches a total even briefly has already been seen.
enum TransactionIngest {

    /// Sources a person types or checks field by field before saving. Only
    /// these may arrive confirmed.
    static let personEnteredSources: Set<TransactionSource> = [.manual, .scan]

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
        category: Category? = nil,
        personVerdict: Verdict? = nil,
        receiptImage: Data? = nil,
        into context: ModelContext
    ) -> Result {

        // A verdict arrives with the record only when a person chose it on the
        // Add sheet. From any other source it's ignored, so no parser can ever
        // write a confirmed transaction (D-002, D-034).
        let verdict: Verdict? = personEnteredSources.contains(source)
            ? personVerdict.flatMap { $0 == .unrated ? nil : $0 }
            : nil

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
            verdict: verdict ?? .unrated,
            isConfirmed: verdict != nil,
            // The currency chosen in Profile at the time, so an export says
            // what the person was spending in rather than the model default.
            currencyCode: AppSettings.currencyCode,
            category: category
        )
        incoming.receiptImage = receiptImage

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
                if existing.isConfirmed && !incoming.isConfirmed {
                    incoming.isConfirmed = true
                    incoming.verdict = existing.verdict
                }
            } else {
                incoming.isSuperseded = true
                // Fill gaps in the keeper from the newcomer.
                if keeper.merchant.isEmpty && !incoming.merchant.isEmpty {
                    keeper.setMerchant(incoming.merchant)
                }
                // A person's answer on the Add sheet lands on the record that
                // survives — typing a coffee Wallet already caught still sorts
                // it, rather than vanishing into a superseded copy.
                if incoming.isConfirmed && !keeper.isConfirmed {
                    keeper.isConfirmed = true
                    keeper.verdict = incoming.verdict
                }
                // A receipt photo or note added later belongs to the purchase,
                // whichever record keeps it.
                if keeper.receiptImage == nil { keeper.receiptImage = incoming.receiptImage }
                if keeper.note.isEmpty && !incoming.note.isEmpty { keeper.note = incoming.note }
                if let chosen = incoming.category,
                   incoming.isConfirmed || keeper.category == nil {
                    keeper.category = chosen
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

        // The starter category first, whatever it's been renamed to — Coffee
        // renamed Café still collects Tim Hortons. Then any category with that
        // name. A deleted one simply yields no suggestion: the table never
        // creates categories, because inventing ones nobody asked for is how a
        // tidy list turns into a mess.
        let builtIn = FetchDescriptor<Category>(
            predicate: #Predicate { $0.builtInName == name }
        )
        if let match = (try? context.fetch(builtIn))?.first {
            transaction.category = match
            return
        }
        let byName = FetchDescriptor<Category>(
            predicate: #Predicate { $0.name == name }
        )
        transaction.category = (try? context.fetch(byName))?.first
    }
}
