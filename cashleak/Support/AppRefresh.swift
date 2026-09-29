import Foundation
import SwiftData

/// The catch-up work the app does whenever it might be behind.
///
/// Runs when the app comes to the foreground and when someone pulls to refresh.
/// One function so the two can't drift: a pull that did less than foregrounding
/// would be a gesture that pretends to work.
///
/// What it deliberately can't do is make iCloud sync sooner. There is no API to
/// request a CloudKit import from SwiftData; iOS schedules it. `CloudSyncMonitor`
/// reports on that instead of pretending otherwise.
enum AppRefresh {

    @MainActor
    static func catchUp(in context: ModelContext) async {
        // Recurring bills that fell due while the app sat open or suspended.
        RecurringPoster.postDue(in: context)
        // Anything the intent or a sync wrote that hasn't hit disk yet.
        try? context.save()
        await DailyReminderScheduler.refresh(in: context)
        WidgetSnapshotUpdater.refresh(in: context)
    }
}
