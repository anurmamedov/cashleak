import SwiftUI

/// Every month at a glance, for jumping further back than the arrows make
/// comfortable (D-040). Opened by tapping the month name on Overview.
///
/// Each cell shows what was spent and an orange line for the share that
/// leaked — enough to see which month is worth opening without opening them
/// all.
struct MonthPickerSheet: View {

    let years: [MonthGrid.Year]
    let selected: Date
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss

    private let brand = Color(hex: "C65A2E")
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(years) { year in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(year.year))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(year.cells) { cell in
                                    monthCell(cell)
                                }
                            }
                        }
                    }

                    Text("Orange line: the share of that month that leaked.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pick a month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(brand)
        .presentationDetents([.medium, .large])
    }

    private func monthCell(_ cell: MonthGrid.Cell) -> some View {
        let isSelected = Calendar.current.isDate(cell.month, equalTo: selected, toGranularity: .month)
        return Button {
            onPick(cell.month)
            dismiss()
        } label: {
            VStack(spacing: 3) {
                Text(cell.month.formatted(.dateTime.month(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(cell.isAvailable && cell.spent > 0 ? compact(cell.spent) : "–")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                GeometryReader { proxy in
                    Capsule()
                        .fill(brand)
                        .frame(width: proxy.size.width * min(max(cell.leakShare, 0), 1))
                }
                .frame(height: 3)
                .padding(.horizontal, 6)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? brand : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(!cell.isAvailable)
        .opacity(cell.isAvailable ? 1 : 0.3)
        .accessibilityLabel(accessibilityText(cell))
    }

    /// "$820", "$2.4k" — glanceable, not accounting.
    private func compact(_ value: Double) -> String {
        guard value >= 1000 else { return value.currencyRounded }
        return (value / 1000).currency(code: AppSettings.currencyCode, fractionDigits: 1) + "k"
    }

    private func accessibilityText(_ cell: MonthGrid.Cell) -> String {
        let name = cell.month.formatted(.dateTime.month(.wide).year())
        guard cell.isAvailable else { return "\(name), no data" }
        return "\(name), \(cell.spent.currencyRounded) spent, \(Int((cell.leakShare * 100).rounded())) percent leaked"
    }
}
