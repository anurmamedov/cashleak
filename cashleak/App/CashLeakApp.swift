import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseCore
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let navigation = AppNavigation()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseBootstrap.configureIfNeeded()
        // Before the model container exists, so the first iCloud import on a
        // fresh install is observed from its start rather than half-way through.
        _ = CloudSyncMonitor.shared
        UNUserNotificationCenter.current().delegate = self
        BackgroundRefresh.register()
        BackgroundRefresh.schedule()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        navigation.open(userInfo: response.notification.request.content.userInfo)
    }
}

@main
struct CashLeakApp: App {

    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            AppGate()
                .environmentObject(appDelegate.navigation)
                .onOpenURL { appDelegate.navigation.open(url: $0) }
                .task {
                    let context = AppModelContainer.shared.mainContext
                    SeedData.seedCategoriesIfNeeded(in: context)
                    HistoryMaintenance.purgeOldMergedDuplicates(in: context)
                    RecurringPoster.postDue(in: context)
                    await DailyReminderScheduler.refresh(in: context)
                    WidgetSnapshotUpdater.refresh(in: context)
                }
        }
        .modelContainer(AppModelContainer.shared)
        .onChange(of: scenePhase) { _, phase in
            // Also on foreground: someone who leaves the app open for days
            // would otherwise never see their rent post. Safe to call twice —
            // rules advance past `now` before returning.
            switch phase {
            case .active:
                // Same work as pull-to-refresh — see `AppRefresh`.
                Task { await AppRefresh.catchUp(in: AppModelContainer.shared.mainContext) }
            case .background:
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
    }
}

/// Decides what the user sees: welcome, lock screen, or the app.
///
/// The order matters. A profile is required before the tabs appear, and the
/// lock — if one is set — sits in front of everything after a backgrounding.
struct AppGate: View {

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    @StateObject private var authentication = AuthenticationService()
    @State private var isLocked = AppLock.isEnabled
    /// When the app went to the background. Used to avoid re-locking on a
    /// momentary switch away — being asked for a password after glancing at a
    /// notification is how people turn locks off.
    @State private var backgroundedAt: Date?
    @State private var offeringLock = false

    /// Five minutes. A quick trip to Messages and back shouldn't need Face ID;
    /// at one minute it felt like being asked to log in all the time.
    private static let lockGracePeriod: TimeInterval = 5 * 60

    var body: some View {
        Group {
            if !authentication.isReady {
                ProgressView("Preparing CashLeak…")
            } else if authentication.user == nil {
                WelcomeView()
            } else if profiles.isEmpty {
                ProgressView("Restoring your profile…")
                    .task(id: authentication.user?.uid) {
                        createLocalProfileIfNeeded()
                    }
            } else if isLocked {
                LockScreenView { isLocked = false }
            } else {
                RootTabView()
                    .task {
                        // Asked once, the first time the app is open and
                        // signed in. Signed in stays signed in; this only
                        // decides whether opening the app needs a glance.
                        guard AppLock.shouldOfferDeviceAuthentication else { return }
                        try? await Task.sleep(for: .seconds(0.6))
                        AppLock.markDeviceAuthenticationOffered()
                        offeringLock = true
                    }
            }
        }
        .alert(
            "You're signed in",
            isPresented: $offeringLock
        ) {
            Button("Use \(AppLock.biometryName)") {
                Task { _ = await AppLock.enableDeviceAuthentication() }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("You'll stay signed in on this iPhone. \(AppLock.biometryName) keeps your spending private if someone else picks it up. You can change this in Profile › App lock.")
        }
        .environmentObject(authentication)
        .animation(.easeInOut(duration: 0.2), value: authentication.user?.uid)
        // After a confirmed email change the account's email moves on; the
        // profile and the saved Face ID sign-in follow it.
        .task(id: authentication.user?.email) { syncEmail() }
        // Accounts from earlier versions carried the name; once the profile
        // has it, it's removed from the account (D-029).
        .task(id: authentication.user?.uid) {
            if !profiles.isEmpty { await authentication.clearStoredName() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = .now
            case .active:
                Task { await authentication.refreshUser() }
                guard AppLock.isEnabled, let since = backgroundedAt else { return }
                if Date.now.timeIntervalSince(since) > Self.lockGracePeriod {
                    isLocked = true
                }
                backgroundedAt = nil
            default:
                break
            }
        }
    }

    @MainActor
    private func syncEmail() {
        guard let email = authentication.user?.email?.lowercased(), !email.isEmpty,
              let profile = profiles.first, profile.email.lowercased() != email else { return }
        profile.email = email
        try? context.save()
        // The saved password belongs to the old address. It still works with
        // the new one, but the saved email it's filed under doesn't — the next
        // password sign-in saves it again.
        if let saved = SavedSignIn.savedEmail, saved != email { SavedSignIn.forget() }
    }

    @MainActor
    private func createLocalProfileIfNeeded() {
        guard profiles.isEmpty, let user = authentication.user else { return }

        // Apple's name if this was a first Apple sign-in; otherwise a name an
        // earlier version stored with the account, which is then cleared.
        let first: String
        let last: String
        if let apple = authentication.consumePendingAppleName() {
            first = apple.givenName ?? ""
            last = apple.familyName ?? ""
        } else {
            let parts = (authentication.legacyDisplayName ?? "")
                .split(separator: " ", maxSplits: 1)
                .map(String.init)
            first = parts.first ?? ""
            last = parts.count > 1 ? parts[1] : ""
        }

        let providers = Set(user.providerData.map(\.providerID))
        let profile = UserProfile(
            firstName: first,
            lastName: last,
            email: user.email ?? "",
            signInMethod: providers.contains("apple.com") ? .apple : .email,
            appleUserID: providers.contains("apple.com") ? user.uid : nil
        )
        context.insert(profile)
        try? context.save()
        Task { await authentication.clearStoredName() }
    }
}
