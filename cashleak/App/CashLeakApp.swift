import SwiftUI
import SwiftData

@main
struct CashLeakApp: App {

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppGate()
                .task {
                    let context = AppModelContainer.shared.mainContext
                    SeedData.seedCategoriesIfNeeded(in: context)
                    RecurringPoster.postDue(in: context)
                }
        }
        .modelContainer(AppModelContainer.shared)
        .onChange(of: scenePhase) { _, phase in
            // Also on foreground: someone who leaves the app open for days
            // would otherwise never see their rent post. Safe to call twice —
            // rules advance past `now` before returning.
            guard phase == .active else { return }
            RecurringPoster.postDue(in: AppModelContainer.shared.mainContext)
        }
    }
}

/// Decides what the user sees: welcome, lock screen, or the app.
///
/// The order matters. A profile is required before the tabs appear, and the
/// lock — if one is set — sits in front of everything after a backgrounding.
struct AppGate: View {

    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]

    @State private var isLocked = AppLock.isEnabled
    /// When the app went to the background. Used to avoid re-locking on a
    /// momentary switch away — being asked for a password after glancing at a
    /// notification is how people turn locks off.
    @State private var backgroundedAt: Date?

    private static let lockGracePeriod: TimeInterval = 60

    var body: some View {
        Group {
            if profiles.isEmpty {
                WelcomeView()
            } else if isLocked {
                LockScreenView { isLocked = false }
            } else {
                RootTabView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: profiles.isEmpty)
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
}
