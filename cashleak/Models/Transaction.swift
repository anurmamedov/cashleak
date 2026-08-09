import Foundation
import SwiftData

/// A single purchase.
///
/// CloudKit constraints (see ARCHITECTURE.md): every stored property has a
/// default value, there is no `@Attribute(.unique)`, and every relationship is
/// optional with an explicit inverse declared on the other side.
///
/// Note on the name: `StoreKit` also defines a `Transaction`. When StoreKit is
/// introduced in P3, refer to that one as `StoreKit.Transaction` rather than
/// renaming this model.
@Model
final class Transaction {

    // MARK: Stored

    var amount: Double = 0
    var currencyCode: String = "CAD"
    var date: Date = Date.distantPast

    /// As captured, unmodified. Kept for display and for correcting a bad parse.
    var merchant: String = ""

    /// Lowercased, stripped of store numbers and processor prefixes.
    /// Written on every save; used by the dedup matcher in L14.
    var normalizedMerchant: String = ""

    var note: String = ""

    /// "This transaction is real." Distinct from `verdict` — see DECISIONS.md.
    /// Nothing counts toward a total until this is true.
    var isConfirmed: Bool = false

    /// Set when the dedup matcher decides this record duplicates another.
    /// Superseded records are excluded from every aggregate but never deleted,
    /// so a wrong merge stays recoverable.
    var isSuperseded: Bool = false

    @Attribute(.externalStorage) var receiptImage: Data?

    // MARK: Raw enum storage

    /// Backing store for `source`. Use the computed property instead.
    var sourceRaw: String = TransactionSource.manual.rawValue

    /// Backing store for `verdict`. Use the computed property instead.
    var verdictRaw: String = Verdict.unrated.rawValue

    // MARK: Relationships

    var category: Category?
    var trip: Trip?

    // MARK: Computed

    var source: TransactionSource {
        get { TransactionSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var verdict: Verdict {
        get { Verdict(rawValue: verdictRaw) ?? .unrated }
        set { verdictRaw = newValue.rawValue }
    }

    /// A transaction counts toward totals only once a human has confirmed it
    /// and it hasn't been merged away.
    var countsTowardTotals: Bool {
        isConfirmed && !isSuperseded
    }

    /// Waiting in the Sort queue.
    var needsSorting: Bool {
        !isConfirmed && !isSuperseded
    }

    // MARK: Init

    init(
        amount: Double,
        date: Date = .now,
        merchant: String = "",
        note: String = "",
        source: TransactionSource = .manual,
        verdict: Verdict = .unrated,
        isConfirmed: Bool = false,
        currencyCode: String = "CAD",
        category: Category? = nil,
        trip: Trip? = nil
    ) {
        self.amount = amount
        self.date = date
        self.merchant = merchant
        self.normalizedMerchant = MerchantNormalizer.normalize(merchant)
        self.note = note
        self.sourceRaw = source.rawValue
        self.verdictRaw = verdict.rawValue
        self.isConfirmed = isConfirmed
        self.isSuperseded = false
        self.currencyCode = currencyCode
        self.category = category
        self.trip = trip
    }

    /// Updates `merchant` and keeps `normalizedMerchant` in step.
    /// Always set the merchant through this — a stale normalized value breaks
    /// deduplication silently.
    func setMerchant(_ newValue: String) {
        merchant = newValue
        normalizedMerchant = MerchantNormalizer.normalize(newValue)
    }
}
