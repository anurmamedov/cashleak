import Foundation

/// How fresh Overview's numbers are, in a few words for the line under the
/// month (D-037).
///
/// "Up to date" only while it's true — the first ten seconds after an iCloud
/// sync finished or a pull checked. After that the line says how long ago, in
/// steps that don't flicker: 10 and 30 seconds, each minute to nine, then
/// 10, 15, 20, 30, 45 minutes, then a clock time.
enum SyncFreshness {

    enum State: Equatable {
        case upToDate
        case ago(String)
        case offline(String)
    }

    /// Below this, "up to date" is the honest wording.
    static let freshWindow: TimeInterval = 10

    /// `nil` when nothing is known — the greeting then shows on its own rather
    /// than claim anything.
    static func state(
        lastSync: Date?,
        isOffline: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> State? {
        if isOffline {
            let detail = lastSync.map { agoText(since: $0, now: now, calendar: calendar) }
                ?? "showing what's on this phone"
            return .offline("offline · " + detail)
        }
        guard let lastSync else { return nil }
        if now.timeIntervalSince(lastSync) < freshWindow { return .upToDate }
        return .ago(agoText(since: lastSync, now: now, calendar: calendar))
    }

    private static let minuteSteps = [45, 30, 20, 15, 10]

    static func agoText(since date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))

        if elapsed < 10 { return "updated just now" }
        if elapsed < 30 { return "updated 10 sec ago" }
        if elapsed < 60 { return "updated 30 sec ago" }

        let minutes = Int(elapsed / 60)
        if minutes < 10 { return "updated \(minutes) min ago" }
        if minutes < 60 {
            let step = minuteSteps.first { minutes >= $0 } ?? 10
            return "updated \(step) min ago"
        }

        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "updated at \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "updated yesterday, \(time)"
        }
        return "updated \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }
}
