import SwiftUI
import SwiftData

@main
struct CashLeakApp: App {

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
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
