import Foundation
import SwiftData

/// What the Profile card shows under your name, and what "Delete account" can
/// erase.
enum AccountData {

    // MARK: Stats

    /// How CashLeak is set up for you — not how you spend. Spending lives on
    /// Overview and Analysis; repeating it here only invites a second, slightly
    /// different number (D-039).
    struct Stats: Equatable {
        /// Share of purchases that arrived without typing: Apple Pay, bank
        /// alerts, recurring bills. A drop means capture broke. `nil` with no
        /// purchases.
        let caughtShare: Double?
        /// Waiting in Sort right now.
        let waiting: Int
        /// The earliest purchase on record.
        let since: Date?
    }

    /// Sources that need no typing. A receipt scan still needs a person.
    static let automaticSources: Set<TransactionSource> = [.applePay, .bankAlert, .recurring]

    /// Merged duplicates don't count — one purchase is one purchase.
    static func stats(from transactions: [Transaction]) -> Stats {
        let live = transactions.filter { !$0.isSuperseded }
        let automatic = live.filter { automaticSources.contains($0.source) }.count
        return Stats(
            caughtShare: live.isEmpty ? nil : Double(automatic) / Double(live.count),
            waiting: live.filter(\.needsSorting).count,
            since: live.map(\.date).min()
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
