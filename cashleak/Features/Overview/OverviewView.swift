import SwiftUI
import SwiftData

/// The screen that states the product thesis in its top third.
struct OverviewView: View {

    @Environment(\.colorScheme) private var colorScheme
    @Query private var transactions: [Transaction]
    @Query(sort: \Trip.startDate) private var trips: [Trip]

    private var summary: SpendingSummary {
        SpendingSummary.make(from: transactions)
    }

    private var leaksByCategory: [(category: Category?, total: Double)] {
        Array(SpendingSummary.leaksByCategory(from: transactions).prefix(4))
    }

    private var activeTrip: Trip? {
        trips.first(where: \.isActive) ?? trips.first(where: \.isUpcoming)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    leakCard
                    statsRow
                    if !leaksByCategory.isEmpty { leakBreakdown }
                    if let trip = activeTrip { tripCard(trip) }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle(Date.now.formatted(.dateTime.month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Leak card

    private var leakCard: some View {
        let ratio = summary.leakRatio
        let background = LeakRamp.color(
            ratio: ratio,
            transactionCount: summary.transactionCount,
            daysOfHistory: summary.daysOfHistory,
            colorScheme: colorScheme
        )
        let foreground = LeakRamp.foreground(ratio: ratio, colorScheme: colorScheme)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Leaked this month")
                .font(.footnote)
                .foregroundStyle(foreground.opacity(0.75))

            Text(summary.leaked.currencyRounded)
                .font(.system(size: 46, weight: .medium, design: .default))
                .foregroundStyle(foreground)
                .contentTransition(.numericText())

            Text(tradeOffLine)
                .font(.callout.italic())
                .foregroundStyle(foreground.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeInOut(duration: 0.4), value: ratio)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Leaked this month, \(summary.leaked.currencyRounded). \(tradeOffLine)")
    }

    /// States the number and the trade-off, then stops. Never scolds.
    private var tradeOffLine: String {
        guard summary.transactionCount > 0 else {
            return "Nothing sorted yet this month."
        }
        if let trip = activeTrip, trip.estimatedBudget > 0 {
            let share = Int((summary.leaked / trip.estimatedBudget * 100).rounded())
            if share > 0 {
                return "That's \(share)% of your trip to \(trip.destination.isEmpty ? trip.name : trip.destination)."
            }
        }
        let percent = Int((summary.leakRatio * 100).rounded())
        return "\(percent)% of what you spent this month."
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            stat("Spent", summary.spent.currencyRounded, tint: .primary)
            stat("Pace", summary.pace.currencyRounded, tint: .primary)
            stat("Kept", summary.kept.currencyRounded, tint: Color(hex: "0F6E56"))
        }
    }

    private func stat(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.medium))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Breakdown

    private var leakBreakdown: some View {
        let maximum = leaksByCategory.map(\.total).max() ?? 1

        return VStack(alignment: .leading, spacing: 12) {
            Text("Where it leaks")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(Array(leaksByCategory.enumerated()), id: \.offset) { _, row in
                VStack(spacing: 5) {
                    HStack {
                        Text(row.category?.name ?? "Uncategorised")
                            .font(.subheadline)
                        Spacer()
                        Text(row.total.currencyRounded)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(.tertiarySystemFill))
                            Capsule()
                                .fill(Color(hex: row.category?.colorHex ?? "D85A30"))
                                .frame(width: geometry.size.width * (row.total / maximum))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
    }

    // MARK: Trip

    private func tripCard(_ trip: Trip) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.name)
                    .font(.subheadline.weight(.medium))
                Text(tripSubtitle(trip))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    private func tripSubtitle(_ trip: Trip) -> String {
        if trip.isActive {
            return "\(trip.daysRemaining) days left · \(trip.actualSpend.currencyRounded) of \(trip.estimatedBudget.currencyRounded)"
        }
        let days = Calendar.current.dateComponents([.day], from: .now, to: trip.startDate).day ?? 0
        return "In \(days) days · \(trip.estimatedBudget.currencyRounded) estimated"
    }
}
