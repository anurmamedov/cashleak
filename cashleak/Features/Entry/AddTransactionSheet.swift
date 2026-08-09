import SwiftUI
import SwiftData

/// Number pad first. Amount → category chip → done.
///
/// The target is under five seconds without looking, which is why there's no
/// date picker, no required note, and no merchant field in the primary path.
/// Anything that can be edited later in Sort doesn't belong here.
struct AddTransactionSheet: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var digits = ""
    @State private var selectedCategory: Category?
    @State private var merchant = ""

    private var amount: Double {
        (Double(digits) ?? 0) / 100
    }

    private var canSave: Bool { amount > 0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                amountDisplay
                categoryChips
                Divider()
                NumberPad(
                    onDigit: append,
                    onDelete: deleteLast
                )
                saveButton
            }
            .navigationTitle("Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var amountDisplay: some View {
        Text(amount.currencyExact)
            .font(.system(size: 52, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(canSave ? .primary : .tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.15), value: digits)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { category in
                    let isSelected = selectedCategory?.persistentModelID == category.persistentModelID
                    Button {
                        selectedCategory = isSelected ? nil : category
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: category.icon)
                                .font(.caption)
                            Text(category.name)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            isSelected
                                ? Color(hex: category.colorHex).opacity(0.22)
                                : Color(.secondarySystemBackground)
                        )
                        .overlay(
                            Capsule().stroke(
                                isSelected ? Color(hex: category.colorHex) : .clear,
                                lineWidth: 1
                            )
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("Save")
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!canSave)
        .padding()
    }

    // MARK: Actions

    private func append(_ digit: String) {
        guard digits.count < 9 else { return }
        if digits.isEmpty && digit == "0" { return }
        digits.append(digit)
    }

    private func deleteLast() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
    }

    private func save() {
        guard canSave else { return }

        // Manual entries are confirmed on save — the user is looking right at
        // the amount they just typed. Nothing else in the app gets this
        // shortcut; every automated source goes through Sort unconfirmed.
        let transaction = Transaction(
            amount: amount,
            date: .now,
            merchant: merchant,
            source: .manual,
            verdict: .unrated,
            isConfirmed: true,
            category: selectedCategory
        )
        context.insert(transaction)
        try? context.save()

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// Large hit targets, no decimal key — digits accumulate from the right so
/// `450` reads as `$4.50`. One less thing to think about while paying.
private struct NumberPad: View {

    let onDigit: (String) -> Void
    let onDelete: () -> Void

    private let rows = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(row, id: \.self) { key in
                        padButton(key) { onDigit(key) }
                    }
                }
            }
            HStack(spacing: 0) {
                Color.clear.frame(maxWidth: .infinity, maxHeight: 60)
                padButton("0") { onDigit("0") }
                Button(action: onDelete) {
                    Image(systemName: "delete.left")
                        .font(.title3)
                        .frame(maxWidth: .infinity, maxHeight: 60)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete")
            }
        }
    }

    private func padButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.title2)
                .frame(maxWidth: .infinity, maxHeight: 60)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
