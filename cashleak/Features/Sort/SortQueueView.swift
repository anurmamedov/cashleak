import SwiftUI
import SwiftData

/// One queue for everything, regardless of source.
///
/// A swipe sets the verdict **and** confirms in a single gesture — that's the
/// core loop. The two fields stay independent in the model, but at the point of
/// judgement the user is saying both "this is real" and "here's my call".
///
/// **Select** acts on several at once, in three taps: Select, tick (or Select
/// all), then Worth it, Leak, Category or Remove. No hidden gestures and no
/// confirmation pop-ups — every action, removal included, has Undo instead.
/// Bulk verdicts go through the same `SortBatch.apply` as a swipe (D-021).
struct SortQueueView: View {

    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<Transaction> { !$0.isConfirmed && !$0.isSuperseded },
        sort: \Transaction.date,
        order: .reverse
    )
    private var queue: [Transaction]

    @State private var categorising: Transaction?
    @State private var choosingBulkCategory = false

    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<PersistentIdentifier>()

    @State private var pendingUndo: PendingUndo?
    /// Removed but not yet deleted. Hidden from the list while Undo is on
    /// screen and deleted when it goes — holding a deletion back is reliable,
    /// resurrecting a deleted record is not.
    @State private var removing: [Transaction] = []

    /// What the Undo bar would reverse.
    private struct PendingUndo: Equatable {
        let id = UUID()
        let message: String
        /// Field snapshots to restore. Empty for a removal.
        let snapshots: [SortBatch.Snapshot]
        let isRemoval: Bool
    }

    private var isEditing: Bool { editMode == .active }

    /// The queue minus anything waiting to be deleted.
    private var visible: [Transaction] {
        let hidden = Set(removing.map(\.persistentModelID))
        return queue.filter { !hidden.contains($0.persistentModelID) }
    }

    private var selected: [Transaction] {
        visible.filter { selection.contains($0.persistentModelID) }
    }

    private let brand = Color(hex: "C65A2E")
    private let worthIt = Color(hex: "1D9E75")

    var body: some View {
        NavigationStack {
            Group {
                if visible.isEmpty {
                    // Scrollable only so it can be pulled. An empty queue is
                    // exactly when someone who just paid pulls to check.
                    ScrollView {
                        emptyState
                            .containerRelativeFrame(.vertical)
                    }
                    .refreshable { await AppRefresh.catchUp(in: context) }
                } else {
                    list
                        .refreshable { await AppRefresh.catchUp(in: context) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isEditing {
                    actionBar
                } else if let pendingUndo {
                    undoBanner(for: pendingUndo)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(isEditing ? "\(selection.count) selected" : "Sort")
            .navigationBarTitleDisplayMode(isEditing ? .inline : .large)
            .toolbar { toolbarContent }
            .environment(\.editMode, $editMode)
            .sheet(item: $categorising) { transaction in
                CategoryPickerSheet(transaction: transaction)
            }
            .sheet(isPresented: $choosingBulkCategory) {
                BulkCategorySheet(count: selected.count) { category in
                    assign(category, to: selected)
                }
            }
            .onChange(of: visible.count) { _, count in
                // Leave selection mode when there's nothing left to select.
                if count == 0 { endEditing() }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .topBarLeading) {
                let allSelected = !visible.isEmpty && selection.count == visible.count
                Button(allSelected ? "Deselect all" : "Select all") {
                    withAnimation {
                        selection = allSelected ? [] : Set(visible.map(\.persistentModelID))
                    }
                }
                .foregroundStyle(brand)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { endEditing() }
                    .fontWeight(.semibold)
                    .foregroundStyle(brand)
            }
        } else if !visible.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Select") {
                    finalizeRemoval()
                    withAnimation {
                        pendingUndo = nil
                        editMode = .active
                    }
                }
                .foregroundStyle(brand)
            }
        }
    }

    // MARK: List

    private var list: some View {
        List(selection: $selection) {
            Section {
                ForEach(visible) { transaction in
                    NavigationLink {
                        TransactionDetailView(transaction: transaction)
                    } label: {
                        QueueRow(transaction: transaction)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            apply(.worthIt, to: [transaction])
                        } label: {
                            Label("Worth it", systemImage: "checkmark")
                        }
                        .tint(worthIt)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            apply(.leak, to: [transaction])
                        } label: {
                            Label("Leak", systemImage: "drop")
                        }
                        .tint(Color(hex: "D85A30"))
                    }
                }
            } footer: {
                if !isEditing {
                    Text("Swipe right for worth it, left for leak. Tap Select to act on several, or to remove some.")
                }
            }
            .scrollToTopAnchor()
        }
        .listStyle(.plain)
        .tint(brand)
        .scrollsToTopOnTabChange()
    }

    /// The empty state is the reward for clearing the queue, not a blank slate.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(worthIt)
            Text("All sorted")
                .font(.title3.weight(.medium))
            Text("Nothing waiting on you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Action bar

    /// The same four buttons every time. With nothing ticked they're faded and
    /// do nothing — never hidden, so the bar doesn't change shape under a thumb.
    private var actionBar: some View {
        let empty = selected.isEmpty

        return HStack(spacing: 0) {
            barButton("Worth it", systemImage: "checkmark.circle", tint: worthIt) {
                apply(.worthIt, to: selected)
            }
            barButton("Leak", systemImage: "drop", tint: brand) {
                apply(.leak, to: selected)
            }
            barButton("Category", systemImage: "tag", tint: .primary) {
                choosingBulkCategory = true
            }
            barButton("Remove", systemImage: "trash", tint: .red) {
                remove(selected)
            }
        }
        .opacity(empty ? 0.4 : 1)
        .allowsHitTesting(!empty)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func barButton(
        _ title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Undo

    /// Every action can be taken back for a few seconds. An unforgiving version
    /// of the core gesture makes people hesitate, and hesitation is what kills a
    /// daily habit.
    private func undoBanner(for undo: PendingUndo) -> some View {
        HStack {
            Text(undo.message)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Button("Undo") { self.undo(undo) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(hex: "F0997B"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(hex: "2C2C2A"))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    // MARK: Actions

    private func apply(_ verdict: Verdict, to transactions: [Transaction]) {
        guard !transactions.isEmpty else { return }
        finalizeRemoval()

        let snapshots = SortBatch.snapshot(transactions)
        let count = transactions.count
        let label = verdict == .leak ? "leak" : "worth it"
        let message = count == 1
            ? (verdict == .leak ? "Marked as leak" : "Marked worth it")
            : "\(count) marked \(label)"

        withAnimation {
            SortBatch.apply(verdict, to: transactions)
            try? context.save()
            endEditing()
            show(PendingUndo(message: message, snapshots: snapshots, isRemoval: false))
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func assign(_ category: Category, to transactions: [Transaction]) {
        guard !transactions.isEmpty else { return }
        finalizeRemoval()

        let snapshots = SortBatch.snapshot(transactions)
        withAnimation {
            SortBatch.assign(category, to: transactions)
            try? context.save()
            endEditing()
            show(PendingUndo(
                message: "\(transactions.count) filed under \(category.name)",
                snapshots: snapshots,
                isRemoval: false
            ))
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func remove(_ transactions: [Transaction]) {
        guard !transactions.isEmpty else { return }
        finalizeRemoval()

        withAnimation {
            removing = transactions
            endEditing()
            show(PendingUndo(
                message: "\(transactions.count) removed",
                snapshots: [],
                isRemoval: true
            ))
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func undo(_ undo: PendingUndo) {
        withAnimation {
            if undo.isRemoval {
                removing = []
            } else {
                SortBatch.restore(undo.snapshots)
                try? context.save()
            }
            pendingUndo = nil
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    private func show(_ undo: PendingUndo) {
        pendingUndo = undo
        Task {
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                // Only act if nothing newer has replaced it.
                guard pendingUndo?.id == undo.id else { return }
                if undo.isRemoval { finalizeRemoval() }
                withAnimation { pendingUndo = nil }
            }
        }
    }

    /// Deletes whatever is waiting to be removed. Called when the Undo window
    /// closes, and before any new action so an older removal is never lost
    /// track of.
    private func finalizeRemoval() {
        guard !removing.isEmpty else { return }
        SortBatch.remove(removing, in: context)
        removing = []
    }

    private func endEditing() {
        editMode = .inactive
        selection = []
    }
}

/// Picks one category for several purchases at once.
private struct BulkCategorySheet: View {

    let count: Int
    let onPick: (Category) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(categories) { category in
                        Button {
                            onPick(category)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: category.icon)
                                    .foregroundStyle(Color(hex: category.colorHex))
                                    .frame(width: 26)
                                Text(category.name)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                } footer: {
                    Text("Files \(count) purchase\(count == 1 ? "" : "s"). They stay in Sort until you mark them worth it or leak.")
                }
            }
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
