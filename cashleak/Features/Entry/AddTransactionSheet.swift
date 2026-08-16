import SwiftUI
import SwiftData

/// Number pad first. Amount → category chip → done.
///
/// The target is under five seconds without looking, which is why there's no
/// date picker and no required note. The merchant field sits below the amount
/// and stays optional — typing it buys you the remembered category, skipping it
/// costs nothing.
struct AddTransactionSheet: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var digits = ""
    @State private var selectedCategory: Category?
    @State private var merchant = ""
    @State private var suggestions: [String] = []
    @State private var categoryWasAutoFilled = false
    @State private var date = Date.now
    @State private var showingDate = false
    @FocusState private var merchantFocused: Bool

    private var amount: Double {
        (Double(digits) ?? 0) / 100
    }

    private var canSave: Bool { amount > 0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                amountDisplay
                merchantField
                if !suggestions.isEmpty { suggestionRow }
                categoryChips
                dateRow
                Divider()
                NumberPad(onDigit: append, onDelete: deleteLast)
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
            .font(.system(size: 50, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(canSave ? .primary : .tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 22)
            .padding(.bottom, 14)
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.15), value: digits)
    }

    // MARK: Merchant

    private var merchantField: some View {
        TextField("Where (optional)", text: $merchant)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.subheadline)
            .focused($merchantFocused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.words)
            .padding(.bottom, 12)
            .onChange(of: merchant) { _, newValue in
                suggestions = MerchantMemory.recentMerchants(matching: newValue, in: context)
                applyRememberedCategory(for: newValue)
            }
    }

    private var suggestionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        merchant = suggestion
                        suggestions = []
                        merchantFocused = false
                    } label: {
                        Text(suggestion)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
    }

    /// Fills the category from the last time this merchant was filed —
    /// but only while the user hasn't chosen one themselves. An explicit tap
    /// always wins over memory.
    private func applyRememberedCategory(for merchantName: String) {
        guard selectedCategory == nil || categoryWasAutoFilled else { return }

        if let remembered = MerchantMemory.lastCategory(forMerchant: merchantName, in: context) {
            selectedCategory = remembered
            categoryWasAutoFilled = true
        } else if categoryWasAutoFilled {
            selectedCategory = nil
            categoryWasAutoFilled = false
        }
    }

    // MARK: Categories

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { category in
                    let isSelected = selectedCategory?.persistentModelID == category.persistentModelID
                    Button {
                        selectedCategory = isSelected ? nil : category
                        categoryWasAutoFilled = false
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
            .padding(.bottom, 14)
        }
    }

    /// Collapsed by default so the fast path stays fast — but a purchase you
    /// forgot on Tuesday has to be enterable on Wednesday, or the app quietly
    /// demands same-day logging.
    private var dateRow: some View {
        Group {
            if showingDate {
                DatePicker("When", selection: $date, in: ...Date.now)
                    .datePickerStyle(.compact)
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            } else {
                Button {
                    withAnimation { showingDate = true }
                } label: {
                    Label(
                        Calendar.current.isDateInToday(date)
                            ? "Today"
                            : date.formatted(.dateTime.month().day()),
                        systemImage: "calendar"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)
            }
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

        // Manual entries are confirmed on save — the user is looking straight at
        // the amount they just typed. Every automated source goes through Sort
        // unconfirmed instead.
        let transaction = Transaction(
            amount: amount,
            date: date,
            merchant: merchant.trimmingCharacters(in: .whitespaces),
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
                Color.clear.frame(maxWidth: .infinity, maxHeight: 58)
                padButton("0") { onDigit("0") }
                Button(action: onDelete) {
                    Image(systemName: "delete.left")
                        .font(.title3)
                        .frame(maxWidth: .infinity, maxHeight: 58)
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
                .frame(maxWidth: .infinity, maxHeight: 58)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
