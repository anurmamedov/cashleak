import Foundation

/// A deliberately small App Group payload. The widget never opens the user's
/// SwiftData or CloudKit store; the app publishes only the two numbers the
/// widget renders.
struct CashLeakWidgetSnapshot: Codable, Equatable {
    var todaySpent: Double
    var unsortedCount: Int
    var currencyCode: String
    var updatedAt: Date

    static let empty = CashLeakWidgetSnapshot(
        todaySpent: 0,
        unsortedCount: 0,
        currencyCode: Locale.current.currency?.identifier ?? "CAD",
        updatedAt: .distantPast
    )

    /// The widget reloads at midnight even if iOS has not opened the app in the
    /// background. Never carry yesterday's total into a new day.
    func todaySpent(at date: Date = .now, calendar: Calendar = .current) -> Double {
        calendar.isDate(updatedAt, inSameDayAs: date) ? todaySpent : 0
    }
}

enum CashLeakWidgetSnapshotStore {
    static let appGroup = "group.anar.cashleak"
    static let storageKey = "widget.snapshot"

    static func save(_ snapshot: CashLeakWidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func load() -> CashLeakWidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(CashLeakWidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }
}
