import SwiftUI
import SwiftData

/// Placeholder for L17.
///
/// When this is built: range selector, then spent-vs-leaked trend, categories,
/// merchant leaderboard, day-of-week pattern, and one plain-language finding in
/// serif. Every row is a link — dead-end analytics is why people stop opening
/// these screens.
struct AnalysisView: View {

    @Query private var transactions: [Transaction]

    private var summary: SpendingSummary {
        SpendingSummary.make(from: transactions)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("This month") {
                    LabeledContent("Spent", value: summary.spent.currencyRounded)
                    LabeledContent("Leaked", value: summary.leaked.currencyRounded)
                    LabeledContent("Kept", value: summary.kept.currencyRounded)
                    LabeledContent("Leak ratio", value: "\(Int((summary.leakRatio * 100).rounded()))%")
                }

                Section {
                    Text("Charts arrive in L17.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Analysis")
        }
    }
}
