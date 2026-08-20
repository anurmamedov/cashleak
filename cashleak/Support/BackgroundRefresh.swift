import BackgroundTasks
import Foundation
import SwiftData

/// Gives recurring rules a chance to post before the user opens the app.
/// iOS chooses the exact run time; launch and foreground remain the reliable
/// fallback and RecurringPoster is deliberately safe to call more than once.
enum BackgroundRefresh {

    static let identifier = "anar.cashleak.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func schedule(now: Date = .now, calendar: Calendar = .current) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)

        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = nextAfternoon(after: now, calendar: calendar)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Requests the next 15:00 window. This is intentionally well before the
    /// default 21:00 reminder, leaving time for due recurring items to join Sort.
    static func nextAfternoon(after now: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 15
        components.minute = 0
        components.second = 0

        let today = calendar.date(from: components) ?? now
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        var work: Task<Void, Never>?
        task.expirationHandler = { work?.cancel() }

        work = Task { @MainActor in
            guard !Task.isCancelled else {
                task.setTaskCompleted(success: false)
                return
            }

            let context = AppModelContainer.shared.mainContext
            RecurringPoster.postDue(in: context)
            await DailyReminderScheduler.refresh(in: context)
            WidgetSnapshotUpdater.refresh(in: context)
            schedule()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
    }
}
