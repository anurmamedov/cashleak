import SwiftUI
import SwiftData

/// Manage the charges no capture path can see.
///
/// Setup burden is the whole risk here. A user who adds one rule and gives up
/// has a dataset missing their rent, which is worse than no rules at all —
/// their leak ratio will look absurd against a fraction of their real spending.
/// Hence templates, and hence amounts that can be left blank and filled later.
struct RecurringRulesView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringRule.nextRunDate) private var rules: [RecurringRule]
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var isAddingRule = false

    var body: some View {
        List {
            if rules.isEmpty {
                Section {
                    Text("Rent, insurance, subscriptions and bills never reach Apple Pay — they're pre-authorised debits. Rules post them automatically so your month isn't missing its largest numbers.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(rules) { rule in
                ruleRow(rule)
            }
            .onDelete(perform: delete)

            Section {
                Button {
                    isAddingRule = true
                } label: {
                    Label("Add a rule", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Recurring")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isAddingRule) {
            AddRecurringRuleSheet()
        }
    }

    private func ruleRow(_ rule: RecurringRule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.merchant)
                    .font(.body)
                Text("\(rule.cadence.displayName) · next \(rule.nextRunDate.formatted(.dateTime.month().day()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(rule.amount > 0 ? rule.amount.currencyRounded : "Set amount")
                .font(.body)
                .foregroundStyle(rule.amount > 0 ? .primary : .tertiary)
        }
        .opacity(rule.isEnabled ? 1 : 0.5)
        .swipeActions(edge: .leading) {
            Button {
                rule.isEnabled.toggle()
                try? context.save()
            } label: {
                Label(rule.isEnabled ? "Pause" : "Resume",
                      systemImage: rule.isEnabled ? "pause" : "play")
            }
            .tint(.orange)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            context.delete(rules[index])
        }
        try? context.save()
    }
}

/// Templates first, blank form second. Most rules are one of ten things.
struct AddRecurringRuleSheet: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var merchant = ""
    @State private var amountText = ""
    @State private var cadence: Cadence = .monthly
    @State private var nextRunDate = Date.now
    @State private var selectedCategory: Category?

    var body: some View {
        NavigationStack {
            Form {
                Section("Common") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RecurringPoster.templates, id: \.merchant) { template in
                                Button(template.merchant) {
                                    apply(template)
                                }
                                .buttonStyle(.bordered)
                                .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    TextField("Merchant", text: $merchant)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                    Picker("Repeats", selection: $cadence) {
                        ForEach(Cadence.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    DatePicker("Next charge", selection: $nextRunDate, displayedComponents: .date)
                }

                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("None").tag(Category?.none)
                        ForEach(categories) { category in
                            Text(category.name).tag(Category?.some(category))
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            .navigationTitle("New rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(merchant.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func apply(_ template: (merchant: String, amount: Double, cadence: Cadence, category: String)) {
        merchant = template.merchant
        if template.amount > 0 {
            amountText = String(format: "%.2f", template.amount)
        }
        cadence = template.cadence
        selectedCategory = categories.first { $0.name == template.category }
    }

    private func save() {
        let rule = RecurringRule(
            merchant: merchant.trimmingCharacters(in: .whitespaces),
            amount: Double(amountText) ?? 0,
            cadence: cadence,
            nextRunDate: nextRunDate,
            category: selectedCategory
        )
        context.insert(rule)
        try? context.save()
        dismiss()
    }
}
