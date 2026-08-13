import SwiftUI
import SwiftData

/// Decides what the app shows on launch: welcome, lock screen, or the app.
///
/// The order matters. A profile is required before anything else, and if a
/// passcode is set it stands between the profile and the data — including after
/// the app has been backgrounded, which is the case people actually care about.
struct AuthGate: View {

    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [UserProfile]

    @State private var isUnlocked = false
    @State private var backgroundedAt: Date?

    /// How long the app can sit in the background before it relocks.
    ///
    /// Instant relocking makes switching to Shortcuts or Messages — which this
    /// app actively encourages — punishing. A short grace period keeps the lock
    /// meaningful without fighting normal use.
    private let graceInterval: TimeInterval = 60

    private var hasProfile: Bool { !profiles.isEmpty }

    var body: some View {
        Group {
            if !hasProfile {
                WelcomeView()
                    .transition(.opacity)
            } else if AppLock.isEnabled && !isUnlocked {
                LockScreenView {
                    withAnimation { isUnlocked = true }
                }
                .transition(.opacity)
            } else {
                RootTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: hasProfile)
        .onChange(of: scenePhase) { _, phase in
            handle(phase)
        }
        .task {
            // A fresh launch with no passcode is already unlocked.
            if !AppLock.isEnabled { isUnlocked = true }
        }
    }

    private func handle(_ phase: ScenePhase) {
        guard AppLock.isEnabled else {
            isUnlocked = true
            return
        }

        switch phase {
        case .background:
            backgroundedAt = .now
        case .active:
            if let left = backgroundedAt, Date.now.timeIntervalSince(left) > graceInterval {
                isUnlocked = false
            }
            backgroundedAt = nil
        default:
            break
        }
    }
}
