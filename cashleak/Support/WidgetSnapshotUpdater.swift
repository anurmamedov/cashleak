import Foundation
import SwiftData
import WidgetKit

enum WidgetSnapshotBuilder {
    static func make(
        from transactions: [Transaction],
        now: Date = .now,
        calendar: Calendar = .current,
        currencyCode: String = AppSettings.currencyCode
    ) -> CashLeakWidgetSnapshot {
        let todaySpent = transactions
            .filter { $0.countsTowardTotals && calendar.isDate($0.date, inSameDayAs: now) }
            .reduce(0) { $0 + $1.amount }
        let unsortedCount = transactions.filter(\.needsSorting).count

        return CashLeakWidgetSnapshot(
            todaySpent: todaySpent,
            unsortedCount: unsortedCount,
            currencyCode: currencyCode,
            updatedAt: now
        )
    }
}

@MainActor
enum WidgetSnapshotUpdater {
    static func refresh(in context: ModelContext) {
        let transactions = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        refresh(from: transactions)
    }

    static func refresh(from transactions: [Transaction]) {
        CashLeakWidgetSnapshotStore.save(WidgetSnapshotBuilder.make(from: transactions))
        WidgetCenter.shared.reloadTimelines(ofKind: "CashLeakTodayWidget")
    }
}
