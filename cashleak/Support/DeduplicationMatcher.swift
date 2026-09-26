import Foundation

/// Decides whether an incoming transaction is one the store already has.
///
/// The problem this solves is concrete: a single tap-payment can fire the Wallet
/// automation *and* a bank alert, and a receipt scan of the same purchase makes
/// three. Doubled totals in a spending app destroy trust permanently, and the
/// user has no way to tell which number was wrong.
///
/// Match key — all three must hold:
/// - `amount` equal to the cent
/// - `date` within 72 hours
/// - normalized merchants a fuzzy match
///
/// The 72-hour window covers issuer settlement delay: the Wallet trigger fires
/// at the terminal, the bank alert can arrive days later once the charge posts.
enum DeduplicationMatcher {

    /// Issuers settle slowly. Anything tighter misses real duplicates.
    ///
    /// This is the **cross-source** window: the Wallet trigger fires at the
    /// terminal, the bank alert for the same purchase can arrive days later.
    static let window: TimeInterval = 72 * 60 * 60

    /// The **same-source** window, and much tighter on purpose.
    ///
    /// Two Wallet captures of the same amount at the same merchant three hours
    /// apart are not one purchase seen twice. They are two coffees. L3 showed
    /// why this matters now and didn't before: Wallet delivers clean chain names
    /// — `Tim Hortons`, `No Frills` — so a second visit matches the first on
    /// merchant exactly, and small repeat purchases at a chain land on the same
    /// amount constantly. Under the 72-hour rule the second coffee was silently
    /// merged away and the user's total was quietly wrong.
    ///
    /// A source genuinely firing twice for one purchase does it within seconds.
    /// Five minutes is generous and still nowhere near a second visit.
    static let sameSourceWindow: TimeInterval = 5 * 60

    /// Floating point means amounts are never exactly equal — compare in cents.
    static let amountTolerance = 0.005

    /// Existing records that match the candidate, nearest in time first.
    ///
    /// Superseded records are skipped: once something is merged away it can't
    /// pull further records into the same collision.
    /// - Parameter source: where the incoming record came from. Passing it
    ///   narrows the window to `sameSourceWindow` for candidates from the same
    ///   source, which is what stops two genuine visits to the same chain being
    ///   merged. `nil` applies the full window to everything.
    static func matches(
        amount: Double,
        merchant: String,
        date: Date,
        source: TransactionSource? = nil,
        among existing: [Transaction]
    ) -> [Transaction] {

        let normalized = MerchantNormalizer.normalize(merchant)

        return existing
            .filter { candidate in
                guard !candidate.isSuperseded else { return false }
                guard abs(candidate.amount - amount) < amountTolerance else { return false }

                let sameSource = source != nil && candidate.source == source
                let allowed = sameSource ? sameSourceWindow : window
                guard abs(candidate.date.timeIntervalSince(date)) <= allowed else { return false }

                return MerchantNormalizer.isFuzzyMatch(candidate.normalizedMerchant, normalized)
            }
            .sorted { lhs, rhs in
                abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
            }
    }

    static func firstMatch(
        amount: Double,
        merchant: String,
        date: Date,
        source: TransactionSource? = nil,
        among existing: [Transaction]
    ) -> Transaction? {
        matches(
            amount: amount, merchant: merchant, date: date, source: source, among: existing
        ).first
    }

    /// How much a record is worth keeping when two describe the same purchase.
    ///
    /// A human's judgement outranks everything — a sorted transaction carries
    /// work that would be lost by superseding it. Below that, prefer the record
    /// with more information: a receipt, a category, a real merchant string.
    static func richness(of transaction: Transaction) -> Int {
        var score = 0
        if transaction.isConfirmed { score += 8 }
        if transaction.verdict != .unrated { score += 8 }
        if transaction.receiptImage != nil { score += 4 }
        if transaction.category != nil { score += 2 }
        if !transaction.merchant.isEmpty { score += 1 }
        if !transaction.note.isEmpty { score += 1 }
        return score
    }

    /// Of two records for the same purchase, the one to keep.
    ///
    /// Ties go to the incumbent. Churning the stored record for an equally good
    /// newcomer would change `persistentModelID` for no benefit and could
    /// detach it from anything already referencing it.
    static func preferred(_ a: Transaction, _ b: Transaction) -> Transaction {
        richness(of: b) > richness(of: a) ? b : a
    }
}
