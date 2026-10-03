import Foundation
import SwiftData

/// Keeping History tidy without losing anything that matters (D-028).
///
/// History is kept by default and never trimmed automatically: Analysis's year
/// view, the comparisons with last month and the CSV export all read it, and a
/// year of purchases is well under a megabyte. Two things are trimmed:
///
/// - **Merged duplicates**, after 90 days. They're kept only so a wrong merge
///   can be undone, and nobody spots a wrong merge three months on.
/// - **Old purchases**, only when the person asks — Profile › Delete old
///   purchases.
enum HistoryMaintenance {

    static let mergedDuplicateLifetime: TimeInterval = 90 * 24 * 60 * 60

    /// Deletes merged duplicates older than 90 days. Returns how many.
    @MainActor
    @discardableResult
    static func purgeOldMergedDuplicates(now: Date = .now, in context: ModelContext) -> Int {
        let cutoff = now.addingTimeInterval(-mergedDuplicateLifetime)
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.isSuperseded && $0.date < cutoff }
        )
        let old = (try? context.fetch(descriptor)) ?? []
        for transaction in old { context.delete(transaction) }
        if !old.isEmpty { try? context.save() }
        return old.count
    }

    enum Age: Int, CaseIterable, Identifiable {
        case oneYear = 1, twoYears = 2, threeYears = 3

        var id: Int { rawValue }
        var title: String { rawValue == 1 ? "Older than 1 year" : "Older than \(rawValue) years" }
    }

    static func cutoff(for age: Age, now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .year, value: -age.rawValue, to: now) ?? now
    }

    /// Purchases dated before the cutoff, merged duplicates included.
    static func purchases(olderThan cutoff: Date, in transactions: [Transaction]) -> [Transaction] {
        transactions.filter { $0.date < cutoff }
    }

    @MainActor
    static func delete(_ transactions: [Transaction], in context: ModelContext) {
        for transaction in transactions { context.delete(transaction) }
        try? context.save()
    }
}
