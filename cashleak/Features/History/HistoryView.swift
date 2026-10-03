import SwiftUI
import SwiftData

/// Every transaction, searchable.
///
/// Until now the only way to reach a purchase was drilling through Analysis,
/// filtered by range and category — so finding one specific thing from three
/// weeks ago was impossible. Everything has to be reachable, or editing and
/// deleting are theoretical.
struct HistoryView: View {

    @Environment(\.modelContext) private var context

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    @State private var query = ""
    @State private var filter: Filter = .all

    /// Swiped away but not yet deleted — held back while Undo shows, then
    /// deleted, the same way Sort handles removal (D-028).
    @State private var removing: [Transaction] = []
    @State private var undoID = UUID()

    enum Filter: String, CaseIterable, Identifiable {
        case all, leaks, worthIt, unsorted
        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: "All"
            case .leaks: "Leaks"
            case .worthIt: "Worth it"
            case .unsorted: "Unsorted"
            }
        }
    }

    private var filtered: [Transaction] {
        let hidden = Set(removing.map(\.persistentModelID))
        var result = transactions.filter { !$0.isSuperseded && !hidden.contains($0.persistentModelID) }

        switch filter {
        case .all: break
        case .leaks: result = result.filter { $0.verdict == .leak && $0.isConfirmed }
        case .worthIt: result = result.filter { $0.verdict == .worthIt && $0.isConfirmed }
        case .unsorted: result = result.filter(\.needsSorting)
        }

        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return result }

        // Search the normalized merchant too, so "blue bottle" finds
        // "SQ *BLUE BOTTLE #22".
        return result.filter {
            $0.merchant.lowercased().contains(trimmed)
                || $0.normalizedMerchant.contains(trimmed)
                || $0.note.lowercased().contains(trimmed)
                || ($0.category?.name.lowercased().contains(trimmed) ?? false)
        }
    }

    /// Grouped by day, newest first.
    private var sections: [(day: Date, items: [Transaction])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                Section {
                    Text(query.isEmpty ? "Nothing here yet." : "Nothing matches \"\(query)\".")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(sections, id: \.day) { section in
                Section {
                    ForEach(section.items) { transaction in
                        NavigationLink {
                            TransactionDetailView(transaction: transaction)
                        } label: {
                            row(transaction)
                        }
                    }
                    .onDelete { delete($0, in: section.items) }
                } header: {
                    HStack {
                        Text(section.day.formatted(.dateTime.weekday(.abbreviated).month().day()))
                        Spacer()
                        Text(section.items.reduce(0) { $0 + $1.amount }.currencyRounded)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !removing.isEmpty {
                HStack {
                    Text(removing.count == 1 ? "Deleted" : "\(removing.count) deleted")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Undo") {
                        withAnimation { removing = [] }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: "F0997B"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(hex: "2C2C2A"))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal)
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onDisappear(perform: finalizeRemoval)
        .searchable(text: $query, prompt: "Merchant, note or category")
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private func row(_ transaction: Transaction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant.isEmpty ? "Unknown" : transaction.merchant)
                    .font(.body)
                HStack(spacing: 5) {
                    if transaction.needsSorting {
                        Text("Unsorted")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Text(transaction.category?.name ?? "No category")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(transaction.amount.currencyExact)
                .monospacedDigit()
                .foregroundStyle(transaction.verdict == .leak ? Color(hex: "993C1D") : Color.primary)
        }
    }

    private func delete(_ offsets: IndexSet, in items: [Transaction]) {
        finalizeRemoval()
        let picked = offsets.map { items[$0] }
        withAnimation { removing = picked }
        let id = UUID()
        undoID = id
        Task {
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                guard undoID == id else { return }
                withAnimation { finalizeRemoval() }
            }
        }
    }

    /// Deletes whatever is waiting — when Undo closes, before another delete,
    /// or when leaving the screen.
    private func finalizeRemoval() {
        guard !removing.isEmpty else { return }
        for transaction in removing { context.delete(transaction) }
        try? context.save()
        removing = []
    }
}
