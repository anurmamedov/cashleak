import SwiftUI
import SwiftData

/// Placeholder for L20, with the capture setup entry point and the debug tools
/// that make the earlier steps testable.
///
/// When this is built out: per-card automation status, accent picker,
/// notification time, categories, recurring rules, trips, CSV export, privacy.
struct YouView: View {

    @Environment(\.modelContext) private var context
    @Query private var transactions: [Transaction]
    @Query private var categories: [Category]

    private var supersededCount: Int {
        transactions.filter(\.isSuperseded).count
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Capture") {
                    NavigationLink {
                        WalletSetupView()
                    } label: {
                        Label("Apple Pay setup", systemImage: "creditcard")
                    }
                    NavigationLink {
                        RecurringRulesView()
                    } label: {
                        Label("Recurring", systemImage: "repeat")
                    }
                }

                Section("Data") {
                    LabeledContent("Transactions", value: "\(transactions.count - supersededCount)")
                    LabeledContent("Categories", value: "\(categories.count)")
                    if supersededCount > 0 {
                        LabeledContent("Merged duplicates", value: "\(supersededCount)")
                    }
                }

                #if DEBUG
                Section("Debug") {
                    Button("Generate 4 months of data") {
                        SeedData.generate(months: 4, in: context)
                    }
                    Button("Simulate an Apple Pay tap") {
                        TransactionIngest.ingest(
                            amount: Double.random(in: 4...60).rounded(),
                            merchant: ["Blue Bottle", "Uber Eats", "Loblaws", "Shell"].randomElement(),
                            source: .applePay,
                            into: context
                        )
                    }
                    Button("Clear transactions", role: .destructive) {
                        SeedData.clearTransactions(in: context)
                    }
                }
                #endif
            }
            .navigationTitle("You")
        }
    }
}
