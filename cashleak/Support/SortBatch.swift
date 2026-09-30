import Foundation
import SwiftData

/// What Sort does to one purchase or to many, in one place.
///
/// A swipe and a bulk action go through the same functions, so a bulk "Leak"
/// behaves exactly like swiping each purchase left: verdict set, confirmed,
/// counted. Kept out of the view so the parts where being wrong is invisible —
/// undo restoring the right fields, category not confirming — are testable.
enum SortBatch {

    /// Enough to put a purchase back exactly as it was.
    struct Snapshot: Equatable {
        let transaction: Transaction
        let verdict: Verdict
        let isConfirmed: Bool
        let category: Category?
    }

    static func snapshot(_ transactions: [Transaction]) -> [Snapshot] {
        transactions.map {
            Snapshot(
                transaction: $0,
                verdict: $0.verdict,
                isConfirmed: $0.isConfirmed,
                category: $0.category
            )
        }
    }

    /// Sets the verdict **and** confirms — the same two fields a swipe sets.
    /// The user is saying both "this is real" and "here's my call".
    static func apply(_ verdict: Verdict, to transactions: [Transaction]) {
        for transaction in transactions {
            transaction.verdict = verdict
            transaction.isConfirmed = true
        }
    }

    /// Files without judging. Deliberately leaves `isConfirmed` alone:
    /// categorising is filing, confirming is judgement, and collapsing them
    /// would let a tap count a parser's claim toward totals.
    static func assign(_ category: Category, to transactions: [Transaction]) {
        for transaction in transactions {
            transaction.category = category
        }
    }

    /// Restores verdict, confirmation and category together. Restoring the
    /// verdict alone could leave something confirmed with no judgement
    /// attached — the state the model exists to prevent.
    static func restore(_ snapshots: [Snapshot]) {
        for snapshot in snapshots {
            snapshot.transaction.verdict = snapshot.verdict
            snapshot.transaction.isConfirmed = snapshot.isConfirmed
            snapshot.transaction.category = snapshot.category
        }
    }

    /// Deletes for good — the user chose to throw these away.
    ///
    /// Unlike a dedup merge, which marks a record superseded so a wrong merge
    /// can be recovered, this is a person's decision about their own data. The
    /// safety net is Undo in Sort, which holds the deletion back for a few
    /// seconds rather than trying to resurrect a deleted record. The capture
    /// log is a separate model and keeps its entry either way.
    @MainActor
    static func remove(_ transactions: [Transaction], in context: ModelContext) {
        for transaction in transactions {
            context.delete(transaction)
        }
        try? context.save()
    }
}
