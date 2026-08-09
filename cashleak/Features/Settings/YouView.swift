import SwiftUI
import SwiftData

/// Placeholder for L20, with the debug tools that make L9–L16 testable.
///
/// When this is built: Apple Pay card list with per-card automation status and
/// a plain statement of what won't be captured, accent picker, notification
/// time, categories, recurring rules, trips, CSV export, privacy.
struct YouView: View {

    @Environment(\.modelContext) private var context
    @Query private var transactions: [Transaction]
    @Query private var categories: [Category]

    var body: some View {
        NavigationStack {
            List {
                Section("Capture") {
                    LabeledContent("Transactions", value: "\(transactions.count)")
                    LabeledContent("Categories", value: "\(categories.count)")
                }

                Section {
                    Text("Apple Pay captures NFC taps from your phone and watch. It can't see physical card taps, in-app purchases, e-transfers, or cash — those need a recurring rule or a quick manual entry.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("What won't be captured")
                }

                #if DEBUG
                Section("Debug") {
                    Button("Generate 4 months of data") {
                        SeedData.generate(months: 4, in: context)
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
