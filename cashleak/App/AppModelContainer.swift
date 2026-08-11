import Foundation
import SwiftData

/// One container shared by the app and by App Intents.
///
/// The Wallet automation runs the intent in the app's process without bringing
/// the UI forward, so it needs the same store the app uses. Building a second
/// `ModelContainer` would give the intent its own SQLite connection and a stale
/// view of the data.
enum AppModelContainer {

    static let schema = Schema([
        Transaction.self,
        Category.self,
        Trip.self,
        RecurringRule.self,
    ])

    static let shared: ModelContainer = {
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
}
