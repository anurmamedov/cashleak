import Foundation
import SwiftData

/// The rules behind managing categories, kept out of the views so they're
/// testable (D-027).
enum CategoryRules {

    /// Names are compared ignoring case and surrounding spaces: "coffee " and
    /// "Coffee" are the same category to a person, and two of them would split
    /// one habit across two rows everywhere the app groups by name.
    static func isNameTaken(_ name: String, among categories: [Category], excluding current: Category? = nil) -> Bool {
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return false }
        return categories.contains { other in
            other !== current
                && other.name.trimmingCharacters(in: .whitespaces).lowercased() == wanted
        }
    }

    /// Purchases filed here, not counting duplicates merged away.
    static func purchaseCount(_ category: Category) -> Int {
        (category.transactions ?? []).filter { !$0.isSuperseded }.count
    }

    static func deleteMessage(for category: Category) -> String {
        let count = purchaseCount(category)
        switch count {
        case 0: return "It has no purchases."
        case 1: return "1 purchase will become Uncategorised. It isn't deleted."
        default: return "\(count) purchases will become Uncategorised. They aren't deleted."
        }
    }

    /// Deletes the category. Its purchases and recurring bills keep existing
    /// with no category — the relationship nullifies, it never cascades.
    @MainActor
    static func delete(_ category: Category, in context: ModelContext) {
        context.delete(category)
        try? context.save()
    }
}
