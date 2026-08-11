import Foundation
import SwiftData

/// Remembers which category a merchant was last filed under.
///
/// This is what makes repeat entry fast: the second coffee at the same place
/// becomes amount → save, with no category tap. It's also the closest the app
/// comes to guessing on the user's behalf — and it deliberately stops at the
/// category.
///
/// **It never predicts a verdict.** Filing something under Coffee twice says
/// nothing about whether the third one was worth it, and that judgement is the
/// entire product. See D-002.
enum MerchantMemory {

    /// The category most recently used for this merchant.
    ///
    /// Most recent rather than most frequent — a merchant that's been
    /// recategorised should follow the correction immediately, not wait to be
    /// outvoted by history.
    @MainActor
    static func lastCategory(
        forMerchant merchant: String,
        in context: ModelContext
    ) -> Category? {

        let normalized = MerchantNormalizer.normalize(merchant)
        guard !normalized.isEmpty else { return nil }

        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.normalizedMerchant == normalized },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 20

        let matches = (try? context.fetch(descriptor)) ?? []
        return matches.first { $0.category != nil }?.category
    }

    /// Merchants seen before, most recent first, for the entry field's
    /// suggestions.
    @MainActor
    static func recentMerchants(
        matching prefix: String,
        limit: Int = 5,
        in context: ModelContext
    ) -> [String] {

        let trimmed = prefix.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return [] }

        var descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 300

        let recent = (try? context.fetch(descriptor)) ?? []

        var seen = Set<String>()
        var results: [String] = []

        for transaction in recent where !transaction.merchant.isEmpty {
            let key = transaction.normalizedMerchant
            guard key.hasPrefix(trimmed) || transaction.merchant.lowercased().hasPrefix(trimmed) else { continue }
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            results.append(transaction.merchant)
            if results.count >= limit { break }
        }

        return results
    }
}
