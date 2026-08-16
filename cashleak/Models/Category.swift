import Foundation
import SwiftData

/// A spending category.
///
/// Deliberately carries no waste flag, no default verdict, and no
/// auto-classification hook. Whether a purchase was a leak is a property of the
/// purchase, not of its category — see DECISIONS.md D-002.
@Model
final class Category {

    var name: String = ""

    /// SF Symbol name.
    var icon: String = "circle"

    /// Hex string, e.g. `"D85A30"`. Stored as text so the palette can change
    /// without a schema migration.
    var colorHex: String = "888780"

    var kindRaw: String = CategoryKind.want.rawValue

    /// `0` means no budget set.
    var monthlyBudget: Double = 0

    /// Display order in pickers and chips.
    var sortIndex: Int = 0

    @Relationship(inverse: \Transaction.category)
    var transactions: [Transaction]?

    /// Never read by any view — it exists because CloudKit requires an explicit
    /// inverse on *every* relationship, and `RecurringRule.category` had none.
    ///
    /// The omission was invisible until L5: with no iCloud entitlement,
    /// `cloudKitDatabase: .automatic` quietly fell back to a local store and
    /// never validated the schema. The moment the entitlement existed, the
    /// container failed to load at launch.
    @Relationship(inverse: \RecurringRule.category)
    var recurringRules: [RecurringRule]?

    var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .want }
        set { kindRaw = newValue.rawValue }
    }

    var hasBudget: Bool { monthlyBudget > 0 }

    init(
        name: String,
        icon: String = "circle",
        colorHex: String = "888780",
        kind: CategoryKind = .want,
        monthlyBudget: Double = 0,
        sortIndex: Int = 0
    ) {
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.kindRaw = kind.rawValue
        self.monthlyBudget = monthlyBudget
        self.sortIndex = sortIndex
    }
}
