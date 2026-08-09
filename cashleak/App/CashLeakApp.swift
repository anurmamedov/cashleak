import SwiftUI
import SwiftData

@main
struct CashLeakApp: App {

    let modelContainer: ModelContainer = {
        let schema = Schema([
            Transaction.self,
            Category.self,
            Trip.self,
            RecurringRule.self,
        ])

        // CloudKit private database. Switch to `.none` here to test locally
        // without sync — but do the two-device test before building on top of
        // it, per L8.
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .task {
                    SeedData.seedCategoriesIfNeeded(in: modelContainer.mainContext)
                }
        }
        .modelContainer(modelContainer)
    }
}
