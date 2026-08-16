import SwiftUI
import SwiftData

/// Edit or delete a single transaction.
///
/// Its absence was the app's worst flaw: type $450 instead of $45 and the
/// figure sat in your totals permanently. A money app that can't correct a
/// typo isn't trustworthy, and untrustworthy totals make every other screen
/// pointless.
///
/// Also the only place a verdict can be changed after the Sort undo window
/// closes — realising two days later that something *was* a leak is exactly the
/// reflection the product is trying to encourage.
struct TransactionDetailView: View {

    @Bindable var transaction: Transaction

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var amountText = ""
    @State private var merchant = ""
    @State private var note = ""
    @State private var date = Date.now
    @State private var confirmingDelete = false

    private var amount: Double { Double(amountText) ?? 0 }
    private var hasValidAmount: Bool { amount > 0 }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
                TextField("Where", text: $merchant)
                DatePicker("When", selection: $date)
                TextField("Note", text: $note, axis: .vertical)
            } footer: {
                if !hasValidAmount {
                    Text("Amount must be more than zero.")
                        .foregroundStyle(Color(hex: "993C1D"))
                }
            }

            Section("Verdict") {
                Picker("Verdict", selection: Binding(
                    get: { transaction.verdict },
                    set: { setVerdict($0) }
                )) {
                    Text("Worth it").tag(Verdict.worthIt)
                    Text("Leak").tag(Verdict.leak)
                    Text("Unrated").tag(Verdict.unrated)
                }
                .pickerStyle(.segmented)

                Toggle("Confirmed", isOn: Binding(
                    get: { transaction.isConfirmed },
                    set: { transaction.isConfirmed = $0 }
                ))
            }

            Section("Category") {
                Picker("Category", selection: Binding(
                    get: { transaction.category },
                    set: { transaction.category = $0 }
                )) {
                    Text("None").tag(Category?.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(Category?.some(category))
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section {
                LabeledContent("Source", value: transaction.source.badge)
                if transaction.isSuperseded {
                    LabeledContent("Status", value: "Merged duplicate")
                }
                if !transaction.normalizedMerchant.isEmpty {
                    LabeledContent("Matched as", value: transaction.normalizedMerchant)
                }
            } footer: {
                Text("\"Matched as\" is how deduplication sees this merchant. If it looks wrong, two purchases at the same shop may not be recognised as the same place.")
            }

            Section {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete transaction", systemImage: "trash")
                }
            }
        }
        .navigationTitle(transaction.merchant.isEmpty ? "Transaction" : transaction.merchant)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onDisappear(perform: save)
        .confirmationDialog(
            "Delete this transaction?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                context.delete(transaction)
                try? context.save()
                dismiss()
            }
        } message: {
            Text("It'll come out of your totals. This can't be undone.")
        }
    }

    private func load() {
        amountText = String(format: "%.2f", transaction.amount)
        merchant = transaction.merchant
        note = transaction.note
        date = transaction.date
    }

    /// Saves on the way out rather than per keystroke — editing an amount digit
    /// by digit would otherwise rewrite the month's totals on every character.
    private func save() {
        if hasValidAmount { transaction.amount = amount }

        // Goes through `setMerchant` so `normalizedMerchant` stays in step. A
        // stale normalized value breaks dedup silently.
        if merchant != transaction.merchant {
            transaction.setMerchant(merchant.trimmingCharacters(in: .whitespaces))
        }

        transaction.note = note
        transaction.date = date
        try? context.save()
    }

    /// Setting a verdict confirms, because choosing one *is* the judgement.
    /// Clearing it back to unrated unconfirms, returning the row to the queue —
    /// otherwise it would count toward totals with no judgement attached.
    private func setVerdict(_ verdict: Verdict) {
        transaction.verdict = verdict
        if verdict == .unrated {
            transaction.isConfirmed = false
        } else {
            transaction.isConfirmed = true
        }
    }
}
