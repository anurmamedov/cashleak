import SwiftUI
import SwiftData

/// One queue for everything, regardless of source.
///
/// A swipe sets the verdict **and** confirms in a single gesture — that's the
/// core loop. The two fields stay independent in the model, but at the point of
/// judgement the user is saying both "this is real" and "here's my call".
///
/// Tapping a row assigns a category without touching the verdict. Apple Pay
/// capture arrives uncategorised, so without this every automatic transaction
/// would sit outside the Overview breakdown forever.
struct SortQueueView: View {

    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<Transaction> { !$0.isConfirmed && !$0.isSuperseded },
        sort: \Transaction.date,
        order: .reverse
    )
    private var queue: [Transaction]

    @State private var categorising: Transaction?
    @State private var lastAction: SortAction?

    /// Enough to put a transaction back exactly as it was.
    private struct SortAction: Equatable {
        let transaction: Transaction
        let previousVerdict: Verdict
        let previousConfirmed: Bool
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if queue.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }

                if let action = lastAction {
                    undoBanner(for: action)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Sort")
            .sheet(item: $categorising) { transaction in
                CategoryPickerSheet(transaction: transaction)
            }
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(queue) { transaction in
                    NavigationLink {
                        TransactionDetailView(transaction: transaction)
                    } label: {
                        QueueRow(transaction: transaction)
                    }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                apply(.worthIt, to: transaction)
                            } label: {
                                Label("Worth it", systemImage: "checkmark")
                            }
                            .tint(Color(hex: "1D9E75"))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                apply(.leak, to: transaction)
                            } label: {
                                Label("Leak", systemImage: "drop")
                            }
                            .tint(Color(hex: "D85A30"))
                        }
                }
            } footer: {
                Text("Swipe right for worth it, left for leak. Tap to edit.")
            }
        }
        .listStyle(.plain)
    }

    /// The empty state is the reward for clearing the queue, not a blank slate.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color(hex: "1D9E75"))
            Text("All sorted")
                .font(.title3.weight(.medium))
            Text("Nothing waiting on you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Undo

    /// The whole product is one gesture. An unforgiving version of that gesture
    /// makes people hesitate, and hesitation is what kills a daily habit.
    private func undoBanner(for action: SortAction) -> some View {
        HStack {
            Text(action.transaction.verdict == .leak ? "Marked as leak" : "Marked worth it")
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Button("Undo") { undo(action) }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "2C2C2A"))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private func apply(_ verdict: Verdict, to transaction: Transaction) {
        let action = SortAction(
            transaction: transaction,
            previousVerdict: transaction.verdict,
            previousConfirmed: transaction.isConfirmed
        )

        withAnimation {
            transaction.verdict = verdict
            transaction.isConfirmed = true
            try? context.save()
            lastAction = action
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        scheduleBannerDismissal(for: action)
    }

    /// Restores both fields together. Undoing a verdict but leaving the
    /// transaction confirmed would count it toward totals with no judgement
    /// attached — the exact state the model is designed to prevent.
    private func undo(_ action: SortAction) {
        withAnimation {
            action.transaction.verdict = action.previousVerdict
            action.transaction.isConfirmed = action.previousConfirmed
            try? context.save()
            lastAction = nil
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    private func scheduleBannerDismissal(for action: SortAction) {
        Task {
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                // Only clear if nothing newer has replaced it.
                if lastAction == action {
                    withAnimation { lastAction = nil }
                }
            }
        }
    }
}

/// A single queue row. Amount is exact here — this is the moment the user is
/// checking the figure against their memory of the purchase.
private struct QueueRow: View {

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var transaction: Transaction

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(transaction.merchant.isEmpty ? "Unknown" : transaction.merchant)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(transaction.amount.currencyExact)
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        sourceBadge
                        relativeDate
                    }
                    categoryText
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 6) {
                    sourceBadge
                    relativeDate
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    categoryText
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            Button("Worth it") { transaction.verdict = .worthIt; transaction.isConfirmed = true }
            Button("Leak") { transaction.verdict = .leak; transaction.isConfirmed = true }
        }
    }

    private var sourceBadge: some View {
        Text(transaction.source.badge)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var relativeDate: some View {
        Text(transaction.date.formatted(.relative(presentation: .named)))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var categoryText: some View {
        if let category = transaction.category {
            Text(category.name)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("No category")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

/// Assigns a category without touching the verdict.
///
/// Also offers to remember the choice for this merchant, which is how a
/// recurring Apple Pay merchant stops needing a category tap at all.
struct CategoryPickerSheet: View {

    @Bindable var transaction: Transaction
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Category.sortIndex) private var categories: [Category]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(categories) { category in
                        Button {
                            assign(category)
                        } label: {
                            HStack {
                                Image(systemName: category.icon)
                                    .foregroundStyle(Color(hex: category.colorHex))
                                    .frame(width: 26)
                                Text(category.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if transaction.category?.persistentModelID == category.persistentModelID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text(transaction.merchant.isEmpty ? "Category" : transaction.merchant)
                } footer: {
                    Text("Setting a category doesn't confirm the transaction — it stays in the queue until you swipe.")
                }
            }
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func assign(_ category: Category) {
        transaction.category = category
        // Deliberately does not set `isConfirmed`. Categorising is filing;
        // confirming is judgement. Collapsing them would let a tap count a
        // parser's claim toward totals.
        try? context.save()
        dismiss()
    }
}
