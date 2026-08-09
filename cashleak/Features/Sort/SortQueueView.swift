import SwiftUI
import SwiftData

/// One queue for everything, regardless of source.
///
/// A swipe sets the verdict **and** confirms in a single gesture — that's the
/// core loop. The two fields stay independent in the model, but at the point of
/// judgement the user is saying both "this is real" and "here's my call".
struct SortQueueView: View {

    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<Transaction> { !$0.isConfirmed && !$0.isSuperseded },
        sort: \Transaction.date,
        order: .reverse
    )
    private var queue: [Transaction]

    var body: some View {
        NavigationStack {
            Group {
                if queue.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Sort")
        }
    }

    private var list: some View {
        List {
            Section {
                ForEach(queue) { transaction in
                    QueueRow(transaction: transaction)
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
                Text("Swipe right for worth it, left for leak.")
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

    private func apply(_ verdict: Verdict, to transaction: Transaction) {
        withAnimation {
            transaction.verdict = verdict
            transaction.isConfirmed = true
            try? context.save()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// A single queue row. Amount is exact here — this is the moment the user is
/// checking the figure against their memory of the purchase.
private struct QueueRow: View {

    @Bindable var transaction: Transaction

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(transaction.merchant.isEmpty ? "Unknown" : transaction.merchant)
                    .font(.body.weight(.medium))
                Spacer()
                Text(transaction.amount.currencyExact)
                    .font(.body.weight(.medium))
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                Text(transaction.source.badge)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(transaction.date.formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let category = transaction.category {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(category.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
}
