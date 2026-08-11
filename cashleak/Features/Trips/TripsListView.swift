import SwiftUI
import SwiftData

/// Trips list. Reached from the You tab and from the Overview card — not a tab
/// of its own, because it's used a few times a year. See D-006.
struct TripsListView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \Trip.startDate) private var trips: [Trip]
    @State private var isAdding = false

    private var active: [Trip] { trips.filter(\.isActive) }
    private var upcoming: [Trip] { trips.filter(\.isUpcoming) }
    private var past: [Trip] { trips.filter { !$0.isActive && !$0.isUpcoming } }

    var body: some View {
        List {
            if trips.isEmpty {
                Section {
                    Text("A trip turns your leaks into something concrete. Instead of \"$412 wasted\", it's \"35% of Lisbon\".")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !active.isEmpty {
                Section("Now") { ForEach(active) { row($0) } }
            }
            if !upcoming.isEmpty {
                Section("Coming up") { ForEach(upcoming) { row($0) } }
            }
            if !past.isEmpty {
                Section("Been") { ForEach(past) { row($0) } }
            }

            Section {
                Button {
                    isAdding = true
                } label: {
                    Label("Plan a trip", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Trips")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isAdding) { AddTripSheet() }
    }

    private func row(_ trip: Trip) -> some View {
        NavigationLink {
            TripDetailView(trip: trip)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(trip.name)
                        .font(.body)
                    Text(subtitle(trip))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(trip.estimatedBudget.currencyRounded)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(_ trip: Trip) -> String {
        if trip.isActive {
            return "Day \(trip.dayCount - trip.daysRemaining) of \(trip.dayCount)"
        }
        if trip.isUpcoming {
            let days = Calendar.current.dateComponents([.day], from: .now, to: trip.startDate).day ?? 0
            return "In \(days) days · \(trip.dayCount) nights"
        }
        return trip.endDate.formatted(.dateTime.month().year())
    }
}

/// Trip detail — the forecast, and crucially the arithmetic behind it.
///
/// Showing the working is the point. A generic calculator asserts a number;
/// this one demonstrates that the number came from the user's own spending.
struct TripDetailView: View {

    @Bindable var trip: Trip
    @Query private var transactions: [Transaction]

    private var monthLeak: Double {
        SpendingSummary.make(from: transactions).leaked
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                forecastCard
                arithmetic
                if trip.isActive { burnRate }
                if !trip.isActive && !trip.isUpcoming { outcome }
                comparison
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Forecast

    /// Teal, not coral. This is the one screen about what you kept.
    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Estimated for \(trip.dayCount) days")
                .font(.footnote)
                .foregroundStyle(Color(hex: "0F6E56"))

            Text(trip.estimatedBudget.currencyRounded)
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(Color(hex: "04342C"))

            if monthLeak > 0 && trip.estimatedBudget > 0 {
                let share = Int((monthLeak / trip.estimatedBudget * 100).rounded())
                Text("Your \(monthLeak.currencyRounded) of leaks this month is \(share)% of it.")
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Color(hex: "085041"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(hex: "E1F5EE"))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Arithmetic

    private var arithmetic: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How that's built")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                line("Your daily spend", trip.dailyDiscretionaryAtEstimate.currencyRounded)
                Divider()
                line("\(trip.destination.isEmpty ? trip.name : trip.destination) vs \(CityCostIndex.baseline)",
                     String(format: "%.2f×", trip.costMultiplier))
                Divider()
                line("Daily allowance", trip.dailyAllowance.currencyRounded)
                Divider()
                line("Fixed costs", trip.fixedCosts.currencyRounded)
            }
            .padding(.horizontal, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
        .padding(.vertical, 10)
    }

    // MARK: Live

    private var burnRate: some View {
        let elapsed = trip.dayCount - trip.daysRemaining
        let onPace = trip.burnRate <= trip.dailyAllowance
        let progress = trip.estimatedBudget > 0
            ? min(trip.actualSpend / trip.estimatedBudget, 1)
            : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Day \(elapsed) of \(trip.dayCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(trip.burnRate.currencyRounded)/day · \(onPace ? "under" : "over")")
                    .font(.subheadline)
                    .foregroundStyle(onPace ? Color(hex: "0F6E56") : Color(hex: "993C1D"))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(onPace ? Color(hex: "1D9E75") : Color(hex: "D85A30"))
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(trip.actualSpend.currencyRounded) spent")
                Spacer()
                Text("\(trip.estimatedBudget.currencyRounded) planned")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(14)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    /// After the trip, actual against estimate. This is what sharpens the next
    /// forecast.
    private var outcome: some View {
        let delta = trip.actualSpend - trip.estimatedBudget
        let under = delta <= 0

        return VStack(alignment: .leading, spacing: 6) {
            Text("How it went")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(trip.actualSpend.currencyRounded) against \(trip.estimatedBudget.currencyRounded) planned")
                .font(.body)
            Text("\(abs(delta).currencyRounded) \(under ? "under" : "over")")
                .font(.subheadline)
                .foregroundStyle(under ? Color(hex: "0F6E56") : Color(hex: "993C1D"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var comparison: some View {
        Text("A generic calculator says $80 a day for food. You average \(trip.dailyDiscretionaryAtEstimate.currencyRounded).")
            .font(.system(.footnote, design: .serif))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
