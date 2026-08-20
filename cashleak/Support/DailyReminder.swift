import Foundation
import SwiftData
import UserNotifications

/// The actionable daily interruption: only notify when something is waiting
/// for the user's judgement. A zero-count notification is noise, so clearing
/// the Sort queue also removes the pending reminder.
enum DailyReminder {

    static let requestIdentifier = "daily-sort-reminder"
    static let routeKey = "cashleak-route"
    static let sortRoute = "sort"

    struct Plan: Equatable {
        let title: String
        let body: String
        let hour: Int
        let minute: Int

        var dateComponents: DateComponents {
            DateComponents(hour: hour, minute: minute)
        }
    }

    /// Pure so notification wording and time handling can be tested without
    /// asking the Simulator for notification permission.
    static func plan(unsortedCount: Int, hour: Int, minute: Int) -> Plan? {
        guard unsortedCount > 0 else { return nil }

        let safeHour = min(max(hour, 0), 23)
        let safeMinute = min(max(minute, 0), 59)
        let title = unsortedCount == 1
            ? "1 purchase is waiting"
            : "\(unsortedCount) purchases are waiting"

        return Plan(
            title: title,
            body: "Worth it or leak? Sort them while they're still fresh.",
            hour: safeHour,
            minute: safeMinute
        )
    }
}

/// Owns permission and the single repeating notification request.
@MainActor
enum DailyReminderScheduler {

    static func enable(in context: ModelContext) async -> Bool {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            AppSettings.notificationsEnabled = granted
            if granted {
                await refresh(in: context)
            } else {
                center.removePendingNotificationRequests(withIdentifiers: [DailyReminder.requestIdentifier])
            }
            return granted
        } catch {
            AppSettings.notificationsEnabled = false
            center.removePendingNotificationRequests(withIdentifiers: [DailyReminder.requestIdentifier])
            return false
        }
    }

    static func disable() {
        AppSettings.notificationsEnabled = false
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [DailyReminder.requestIdentifier]
        )
    }

    /// Replaces the request whenever the queue count or preferred time changes.
    /// Repeating requests keep working even if iOS never grants a background
    /// refresh window on a particular day.
    static func refresh(in context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        guard AppSettings.notificationsEnabled else {
            center.removePendingNotificationRequests(withIdentifiers: [DailyReminder.requestIdentifier])
            return
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else {
            if settings.authorizationStatus == .denied {
                AppSettings.notificationsEnabled = false
            }
            center.removePendingNotificationRequests(withIdentifiers: [DailyReminder.requestIdentifier])
            return
        }

        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { !$0.isConfirmed && !$0.isSuperseded }
        )
        let count = (try? context.fetchCount(descriptor)) ?? 0
        guard let plan = DailyReminder.plan(
            unsortedCount: count,
            hour: AppSettings.notificationHour,
            minute: AppSettings.notificationMinute
        ) else {
            center.removePendingNotificationRequests(withIdentifiers: [DailyReminder.requestIdentifier])
            return
        }

        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.userInfo = [DailyReminder.routeKey: DailyReminder.sortRoute]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: plan.dateComponents,
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: DailyReminder.requestIdentifier,
            content: content,
            trigger: trigger
        )

        center.removePendingNotificationRequests(withIdentifiers: [DailyReminder.requestIdentifier])
        try? await center.add(request)
    }
}
