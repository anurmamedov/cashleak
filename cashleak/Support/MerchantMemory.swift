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

    /// What the user said the last few times at this merchant (D-035).
    ///
    /// Shown as a line of history — "Last 5 times here: 4 leak · 1 worth it" —
    /// and **never** used to pre-select a verdict. Remembering an answer is
    /// information; filling it in is the app deciding. `nil` until there are
    /// `minimumRated` rated visits, so one purchase doesn't read as a habit.
    struct VerdictHistory: Equatable {
        let leak: Int
        let worthIt: Int
        var total: Int { leak + worthIt }

        var summary: String { "Last \(total) times here: " + counts }

        /// For the narrower Sort row.
        var shortSummary: String { "Last \(total) here: " + counts }

        private var counts: String {
            var parts: [String] = []
            if leak > 0 { parts.append("\(leak) leak") }
            if worthIt > 0 { parts.append("\(worthIt) worth it") }
            return parts.joined(separator: " · ")
        }
    }

    static let minimumRated = 3
    static let historyLength = 5

    @MainActor
    static func verdictHistory(
        forMerchant merchant: String,
        in context: ModelContext
    ) -> VerdictHistory? {

        let normalized = MerchantNormalizer.normalize(merchant)
        guard !normalized.isEmpty else { return nil }

        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate {
                $0.normalizedMerchant == normalized && $0.isConfirmed && !$0.isSuperseded
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 40

        let rated = ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.verdict != .unrated }
            .prefix(historyLength)
        return verdictHistory(of: Array(rated))
    }

    /// The counting, separate from the fetch so it can be tested directly.
    static func verdictHistory(of rated: [Transaction]) -> VerdictHistory? {
        let leak = rated.filter { $0.verdict == .leak }.count
        let worthIt = rated.filter { $0.verdict == .worthIt }.count
        guard leak + worthIt >= minimumRated else { return nil }
        return VerdictHistory(leak: leak, worthIt: worthIt)
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
