import Foundation
import SwiftData

/// Something the user is saving for.
///
/// This is what the leak total gets compared against — the *what* in "tells you
/// what it cost you". Without it the trade-off line collapses to "35% of what
/// you spent this month", which restates the number above it rather than
/// converting it into anything.
///
/// Replaced Trips (D-014). A trip only works for people with travel booked; a
/// goal works for a camera, a deposit, an emergency fund, or a flight — and
/// needs no cost index, no dates, and no burn rate.
@Model
final class Goal {

    var name: String = ""
    var targetAmount: Double = 0

    /// Optional context, e.g. "October, with Dad".
    var note: String = ""

    /// The goal currently used for comparisons. Exactly one at a time — more
    /// than one comparison in the hero line is no comparison at all.
    var isActive: Bool = true

    var createdAt: Date = Date.distantPast

    /// Set when the user marks it reached. Kept rather than deleted so the app
    /// can show what's been achieved.
    var achievedAt: Date?

    var isAchieved: Bool { achievedAt != nil }

    init(name: String, targetAmount: Double, note: String = "", isActive: Bool = true) {
        self.name = name
        self.targetAmount = targetAmount
        self.note = note
        self.isActive = isActive
        self.createdAt = .now
    }

    /// What a given leak total represents against this goal.
    ///
    /// Returns `nil` when there's nothing meaningful to say, so the caller can
    /// fall back rather than print "0% of your camera".
    func share(of leaked: Double) -> Double? {
        guard targetAmount > 0, leaked > 0 else { return nil }
        return leaked / targetAmount
    }

    /// The trade-off sentence.
    ///
    /// Past 100% a percentage stops being a trade-off and becomes arithmetic —
    /// "159% of your camera" is true and reads as nonsense.
    func tradeOffLine(leaked: Double) -> String? {
        guard let share = share(of: leaked) else { return nil }

        if share >= 2 {
            return "That's \(Int(share.rounded(.down))) × \(name)."
        }
        if share >= 1 {
            return "That's more than \(name)."
        }

        let percent = Int((share * 100).rounded())
        guard percent > 0 else { return nil }
        return "That's \(percent)% of \(name)."
    }
}

/// Marks one goal active and clears the rest.
///
/// Enforced here rather than by a database constraint because CloudKit's
/// SwiftData integration doesn't allow unique attributes — the same reason
/// dedup is application logic.
enum GoalStore {

    @MainActor
    static func activate(_ goal: Goal, in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        for other in all {
            other.isActive = (other.persistentModelID == goal.persistentModelID)
        }
        try? context.save()
    }

    /// The goal comparisons should use. Prefers the active one, ignores
    /// anything already achieved.
    static func current(from goals: [Goal]) -> Goal? {
        let live = goals.filter { !$0.isAchieved && $0.targetAmount > 0 }
        return live.first(where: \.isActive) ?? live.first
    }
}
