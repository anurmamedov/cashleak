import Foundation
import SwiftData

/// What the Profile card shows under your name, and what "Delete account" can
/// erase.
enum AccountData {

    // MARK: Stats

    struct Stats: Equatable {
        /// Purchases you've confirmed.
        let sorted: Int
        /// Of what you've judged, the share by amount you said was worth it.
        /// `nil` until something has a verdict.
        let worthItShare: Double?
        /// The date of your earliest sorted purchase.
        let since: Date?
    }

    /// Counted the same way as every total in the app: confirmed, not merged
    /// away.
    static func stats(from transactions: [Transaction]) -> Stats {
        let counted = transactions.filter(\.countsTowardTotals)
        let kept = counted.filter { $0.verdict == .worthIt }.reduce(0) { $0 + $1.amount }
        let leaked = counted.filter { $0.verdict == .leak }.reduce(0) { $0 + $1.amount }
        let judged = kept + leaked
        return Stats(
            sorted: counted.count,
            worthItShare: judged > 0 ? kept / judged : nil,
            since: counted.map(\.date).min()
        )
    }

    // MARK: Erase

    /// Deletes every record CashLeak keeps — purchases, categories, goals,
    /// recurring bills, card labels, the capture log and your profile.
    ///
    /// Record by record rather than a batch delete, so each deletion is mirrored
    /// to iCloud and the data goes from your other devices too. Categories are
    /// re-seeded on next launch, as on a fresh install.
    @MainActor
    static func eraseEverything(in context: ModelContext) {
        deleteAll(Transaction.self, in: context)
        deleteAll(RecurringRule.self, in: context)
        deleteAll(Goal.self, in: context)
        deleteAll(CardAutomation.self, in: context)
        deleteAll(CaptureLogEntry.self, in: context)
        deleteAll(Category.self, in: context)
        deleteAll(UserProfile.self, in: context)
        try? context.save()
        SeedData.resetSeededFlag()
    }

    /// Forgets everything tied to who you are on this phone: the profile, the
    /// saved Face ID sign-in and the app lock. Spending data is untouched.
    @MainActor
    static func forgetIdentity(in context: ModelContext) {
        deleteAll(UserProfile.self, in: context)
        try? context.save()
        SavedSignIn.forget()
        AppLock.removePassword()
        AppLock.disableDeviceAuthentication()
    }

    @MainActor
    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
        for item in all { context.delete(item) }
    }
}
