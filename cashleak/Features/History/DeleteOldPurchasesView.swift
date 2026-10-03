import SwiftUI
import SwiftData

/// For people who'd rather not keep years of purchases. Off the main path,
/// opt-in, and it says exactly how many go before anything does (D-028).
struct DeleteOldPurchasesView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var transactions: [Transaction]

    @State private var age: HistoryMaintenance.Age = .twoYears
    @State private var isConfirming = false
    @State private var exportURL: URL?

    private var matching: [Transaction] {
        HistoryMaintenance.purchases(
            olderThan: HistoryMaintenance.cutoff(for: age),
            in: transactions
        )
    }

    private var countText: String {
        let count = matching.count
        return count == 1 ? "1 purchase" : "\(count) purchases"
    }

    var body: some View {
        Form {
            Section {
                Picker("Delete", selection: $age) {
                    ForEach(HistoryMaintenance.Age.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text(matching.isEmpty
                     ? "Nothing that old yet."
                     : "\(countText) from before \(HistoryMaintenance.cutoff(for: age).formatted(.dateTime.month(.wide).year())). They're removed from this iPhone and your iCloud, and from Analysis.")
            }

            Section {
                Button {
                    exportURL = try? CSVExport.writeTemporaryFile(from: transactions)
                } label: {
                    Label("Export everything first", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("A CSV of all your purchases, to keep somewhere before deleting.")
            }

            Section {
                Button(role: .destructive) {
                    isConfirming = true
                } label: {
                    Text(matching.isEmpty ? "Nothing to delete" : "Delete \(countText)")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .disabled(matching.isEmpty)
            }
        }
        .navigationTitle("Delete old purchases")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color(hex: "C65A2E"))
        .sheet(item: $exportURL) { url in
            ShareSheet(items: [url])
        }
        .confirmationDialog("Delete \(countText)?", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("Delete \(countText)", role: .destructive) {
                HistoryMaintenance.delete(matching, in: context)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }
}
