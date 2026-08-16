import SwiftUI
import SwiftData

/// Manage what you're saving for.
///
/// Deliberately small. A name and an amount is enough to make the leak total
/// mean something, and every extra field is one more reason not to set one up.
struct GoalsView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]

    @State private var editing: Goal?
    @State private var isAdding = false

    private var live: [Goal] { goals.filter { !$0.isAchieved } }
    private var achieved: [Goal] { goals.filter(\.isAchieved) }

    var body: some View {
        List {
            if goals.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What would you rather have?")
                            .font(.subheadline.weight(.medium))
                        Text("A flight, a camera, a deposit. Give it a name and a price, and your leak total stops being an abstract number.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            if !live.isEmpty {
                Section("Saving for") {
                    ForEach(live) { goal in
                        row(goal)
                    }
                    .onDelete { delete($0, from: live) }
                }
            }

            if !achieved.isEmpty {
                Section("Reached") {
                    ForEach(achieved) { goal in
                        HStack {
                            Text(goal.name)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(goal.targetAmount.currencyRounded)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .onDelete { delete($0, from: achieved) }
                }
            }

            Section {
                Button {
                    isAdding = true
                } label: {
                    Label("Add a goal", systemImage: "plus")
                }
            } footer: {
                if live.count > 1 {
                    Text("Tap a goal to compare against it. Only one at a time — two comparisons in one sentence is no comparison at all.")
                }
            }
        }
        .navigationTitle("Goals")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isAdding) { GoalEditor(goal: nil) }
        .sheet(item: $editing) { goal in GoalEditor(goal: goal) }
    }

    private func row(_ goal: Goal) -> some View {
        Button {
            GoalStore.activate(goal, in: context)
        } label: {
            HStack(spacing: 12) {
                // Both branches have to be the same concrete type. `.tertiary`
                // is a ShapeStyle rather than a Color, so mixing it with
                // `Color(hex:)` in a ternary won't type-check.
                Image(systemName: goal.isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(
                        goal.isActive
                            ? Color(hex: AppSettings.accentHex)
                            : Color.secondary.opacity(0.5)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name)
                        .foregroundStyle(.primary)
                    if !goal.note.isEmpty {
                        Text(goal.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(goal.targetAmount.currencyRounded)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading) {
            Button {
                editing = goal
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)

            Button {
                goal.achievedAt = .now
                goal.isActive = false
                try? context.save()
            } label: {
                Label("Reached", systemImage: "checkmark")
            }
            .tint(Color(hex: "1D9E75"))
        }
    }

    private func delete(_ offsets: IndexSet, from list: [Goal]) {
        for index in offsets { context.delete(list[index]) }
        try? context.save()
    }
}

/// Create or edit. One sheet for both — the fields are identical, and a
/// separate "edit" screen would be the same code twice.
struct GoalEditor: View {

    let goal: Goal?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var amountText = ""
    @State private var note = ""

    private var amount: Double { Double(amountText) ?? 0 }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && amount > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What is it?", text: $name)
                        .textInputAutocapitalization(.sentences)
                    TextField("How much?", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("Note (optional)", text: $note)
                } footer: {
                    Text("Your leak total gets compared against this. \"That's 68% of your flight to Lisbon.\"")
                }
            }
            .navigationTitle(goal == nil ? "New goal" : "Edit goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let goal else { return }
        name = goal.name
        amountText = goal.targetAmount > 0 ? String(format: "%.0f", goal.targetAmount) : ""
        note = goal.note
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)

        if let goal {
            goal.name = trimmedName
            goal.targetAmount = amount
            goal.note = note.trimmingCharacters(in: .whitespaces)
        } else {
            let new = Goal(
                name: trimmedName,
                targetAmount: amount,
                note: note.trimmingCharacters(in: .whitespaces)
            )
            context.insert(new)
            GoalStore.activate(new, in: context)
        }

        try? context.save()
        dismiss()
    }
}
