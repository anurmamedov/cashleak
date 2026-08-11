import SwiftUI
import SwiftData

@main
struct CashLeakApp: App {

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    SeedData.seedCategoriesIfNeeded(in: AppModelContainer.shared.mainContext)
                }
        }
        .modelContainer(AppModelContainer.shared)
    }
}
