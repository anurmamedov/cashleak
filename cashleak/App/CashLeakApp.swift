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
                let context = AppModelContainer.shared.mainContext
                RecurringPoster.postDue(in: context)
                Task { await DailyReminderScheduler.refresh(in: context) }
                WidgetSnapshotUpdater.refresh(in: context)
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

    private static let lockGracePeriod: TimeInterval = 60

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
            }
        }
        .environmentObject(authentication)
        .animation(.easeInOut(duration: 0.2), value: authentication.user?.uid)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = .now
            case .active:
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
    private func createLocalProfileIfNeeded() {
        guard profiles.isEmpty, let user = authentication.user else { return }

        let nameParts = (user.displayName ?? "")
            .split(separator: " ", maxSplits: 1)
            .map(String.init)
        let providers = Set(user.providerData.map(\.providerID))
        let profile = UserProfile(
            firstName: nameParts.first ?? "",
            lastName: nameParts.count > 1 ? nameParts[1] : "",
            email: user.email ?? "",
            signInMethod: providers.contains("apple.com") ? .apple : .email,
            appleUserID: providers.contains("apple.com") ? user.uid : nil
        )
        context.insert(profile)
        try? context.save()
    }
}
