import SwiftUI
import SwiftData

/// Plan a trip. The forecast updates live as fields change, so the user sees
/// their own daily spend doing the work rather than a total appearing at the
/// end.
struct AddTripSheet: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var transactions: [Transaction]

    @State private var name = ""
    @State private var selectedCity: CityCostIndex.City?
    @State private var citySearch = ""
    @State private var startDate = Date.now
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var fixedCostsText = ""

    private var dailySpend: Double {
        DiscretionarySpend.dailyAverage(from: transactions) ?? DiscretionarySpend.fallbackDaily
    }

    private var hasEnoughHistory: Bool {
        DiscretionarySpend.dailyAverage(from: transactions) != nil
    }

    private var multiplier: Double { selectedCity?.multiplier ?? 1.0 }
    private var fixedCosts: Double { Double(fixedCostsText) ?? 0 }

    private var days: Int {
        max(Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1, 1)
    }

    private var estimate: Double {
        dailySpend * multiplier * Double(days) + fixedCosts
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && endDate > startDate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)

                    NavigationLink {
                        CityPicker(selection: $selectedCity)
                    } label: {
                        HStack {
                            Text("Destination")
                            Spacer()
                            Text(selectedCity?.displayName ?? "Choose")
                                .foregroundStyle(selectedCity == nil ? .tertiary : .secondary)
                        }
                    }

                    DatePicker("Leaving", selection: $startDate, displayedComponents: .date)
                    DatePicker("Back", selection: $endDate, in: startDate..., displayedComponents: .date)
                    TextField("Flights and lodging", text: $fixedCostsText)
                        .keyboardType(.decimalPad)
                }

                Section {
                    LabeledContent("Your daily spend", value: dailySpend.currencyRounded)
                    if let city = selectedCity {
                        LabeledContent("Cost of living", value: String(format: "%.2f×", city.multiplier))
                        LabeledContent("Daily allowance", value: (dailySpend * city.multiplier).currencyRounded)
                    }
                    LabeledContent("Nights", value: "\(days)")
                    LabeledContent {
                        Text(estimate.currencyRounded)
                            .font(.body.weight(.medium))
                    } label: {
                        Text("Estimate")
                    }
                } header: {
                    Text("Forecast")
                } footer: {
                    if hasEnoughHistory {
                        if let city = selectedCity {
                            Text("\(city.name) is \(CityCostIndex.comparison(for: city.multiplier)). Your allowance is based on what you actually spend, not a generic per-diem.")
                        } else {
                            Text("Based on your own spending over the last 90 days, excluding rent, bills, and subscriptions.")
                        }
                    } else {
                        Text("Not enough history yet, so this uses a placeholder daily figure. It'll get personal after a few weeks of sorting.")
                    }
                }
            }
            .navigationTitle("Plan a trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let trip = Trip(
            name: name.trimmingCharacters(in: .whitespaces),
            destination: selectedCity?.name ?? "",
            startDate: startDate,
            endDate: endDate,
            fixedCosts: fixedCosts,
            costMultiplier: multiplier,
            // Snapshot, not a live reference — a past trip's estimate must not
            // drift as later spending changes the average.
            dailyDiscretionaryAtEstimate: dailySpend
        )
        context.insert(trip)
        try? context.save()
        dismiss()
    }
}

private struct CityPicker: View {

    @Binding var selection: CityCostIndex.City?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List(CityCostIndex.search(query)) { city in
            Button {
                selection = city
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(city.name)
                            .foregroundStyle(.primary)
                        Text(city.country)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(CityCostIndex.comparison(for: city.multiplier))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $query, prompt: "City")
        .navigationTitle("Destination")
        .navigationBarTitleDisplayMode(.inline)
    }
}
