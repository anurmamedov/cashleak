import SwiftUI
import SwiftData
import Charts

/// Range selector, then five sections in order, then one plain-language
/// finding in serif.
///
/// Every row navigates somewhere. Dead-end analytics is why people stop opening
/// these screens — if a chart shows you something interesting and you can't
/// touch it, the screen has wasted your attention.
struct AnalysisView: View {

    @Query private var transactions: [Transaction]
    @State private var range: AnalysisAggregates.Range = .month

    private var trend: [AnalysisAggregates.TrendPoint] {
        AnalysisAggregates.trend(transactions, range: range)
    }

    private var categories: [AnalysisAggregates.CategoryTotal] {
        AnalysisAggregates.categoryLeaks(transactions, range: range)
    }

    private var merchants: [AnalysisAggregates.MerchantTotal] {
        AnalysisAggregates.merchantLeaderboard(transactions, range: range)
    }

    private var weekdays: [AnalysisAggregates.WeekdayTotal] {
        AnalysisAggregates.weekdayPattern(transactions, range: range)
    }

    private var finding: String? {
        AnalysisAggregates.finding(transactions, range: range)
    }

    private var hasData: Bool { !trend.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    rangePicker

                    if hasData {
                        trendSection
                        if !categories.isEmpty { categorySection }
                        if !merchants.isEmpty { merchantSection }
                        weekdaySection
                        if let finding { findingCard(finding) }
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .navigationTitle("Analysis")
            .navigationDestination(for: AnalysisAggregates.MerchantTotal.self) { merchant in
                MerchantDetailView(merchantName: merchant.merchant, range: range)
            }
            .navigationDestination(for: AnalysisAggregates.CategoryTotal.self) { category in
                CategoryDetailView(categoryName: category.name, range: range)
            }
        }
    }

    // MARK: Range

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(AnalysisAggregates.Range.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 4)
    }

    // MARK: Trend

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Spent vs leaked")

            Chart(trend) { point in
                BarMark(
                    x: .value("Date", point.date, unit: range.bucket),
                    y: .value("Kept", point.kept)
                )
                .foregroundStyle(Color(.tertiarySystemFill))

                BarMark(
                    x: .value("Date", point.date, unit: range.bucket),
                    y: .value("Leaked", point.leaked)
                )
                .foregroundStyle(Color(hex: AppSettings.accentHex))
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 160)
        }
    }

    // MARK: Categories

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Leaked by category")

            let maximum = categories.map(\.leaked).max() ?? 1

            ForEach(categories) { category in
                NavigationLink(value: category) {
                    VStack(spacing: 5) {
                        HStack {
                            Text(category.name)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(category.leaked.currencyRounded)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.tertiarySystemFill))
                                Capsule()
                                    .fill(Color(hex: category.colorHex))
                                    .frame(width: geometry.size.width * (category.leaked / maximum))
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Merchants

    private var merchantSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Leaked by merchant")
                .padding(.bottom, 6)

            ForEach(merchants) { merchant in
                NavigationLink(value: merchant) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(merchant.merchant)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text("\(merchant.count) \(merchant.count == 1 ? "visit" : "visits")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(merchant.leaked.currencyRounded)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)

                if merchant.id != merchants.last?.id {
                    Divider()
                }
            }
        }
    }

    // MARK: Weekday

    private var weekdaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("By day of week")

            // Stacked rather than conditionally tinted. The old version turned a
            // bar coral only above a 40% leak share, so at any ordinary ratio
            // every bar stayed grey — a spend chart sitting under a heading
            // about leaks, encoding nothing.
            Chart {
                ForEach(weekdays) { day in
                    BarMark(
                        x: .value("Day", day.shortName),
                        y: .value("Kept", max(day.spent - day.leaked, 0))
                    )
                    .foregroundStyle(Color(.tertiarySystemFill))

                    BarMark(
                        x: .value("Day", day.shortName),
                        y: .value("Leaked", day.leaked)
                    )
                    .foregroundStyle(Color(hex: AppSettings.accentHex))
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 110)

            if let worst = weekdays.filter({ $0.spent > 0 }).max(by: { $0.leakShare < $1.leakShare }),
               worst.leakShare > 0 {
                Text("\(worst.fullName) leaks most — \(Int((worst.leakShare * 100).rounded()))% of what you spend that day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Finding

    /// Serif, because this is the app speaking rather than reporting.
    private func findingCard(_ text: String) -> some View {
        Text(text)
            .font(.system(.body, design: .serif))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing to analyse yet")
                .font(.headline)
            Text("Sort a few purchases and patterns will show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Drill-downs

extension AnalysisAggregates.MerchantTotal: Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.merchant == rhs.merchant }
    func hash(into hasher: inout Hasher) { hasher.combine(merchant) }
}

extension AnalysisAggregates.CategoryTotal: Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

/// Every transaction at one merchant. The end of the chain — this is what the
/// leaderboard row was pointing at.
struct MerchantDetailView: View {

    let merchantName: String
    let range: AnalysisAggregates.Range

    @Query private var transactions: [Transaction]

    private var matching: [Transaction] {
        AnalysisAggregates.counted(transactions, in: range)
            .filter { $0.merchant == merchantName }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Visits", value: "\(matching.count)")
                LabeledContent("Total", value: matching.reduce(0) { $0 + $1.amount }.currencyRounded)
                LabeledContent(
                    "Leaked",
                    value: matching.filter { $0.verdict == .leak }
                        .reduce(0) { $0 + $1.amount }.currencyRounded
                )
            }

            Section("Every visit") {
                ForEach(matching) { transaction in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(transaction.date.formatted(.dateTime.month().day()))
                                .font(.subheadline)
                            if transaction.verdict == .leak {
                                Text("Leak")
                                    .font(.caption)
                                    .foregroundStyle(Color(hex: "993C1D"))
                            }
                        }
                        Spacer()
                        Text(transaction.amount.currencyExact)
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle(merchantName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Every leak in one category.
struct CategoryDetailView: View {

    let categoryName: String
    let range: AnalysisAggregates.Range

    @Query private var transactions: [Transaction]

    private var matching: [Transaction] {
        AnalysisAggregates.counted(transactions, in: range)
            .filter { ($0.category?.name ?? "Uncategorised") == categoryName }
            .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        List {
            ForEach(matching) { transaction in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(transaction.merchant.isEmpty ? "Unknown" : transaction.merchant)
                            .font(.subheadline)
                        Text(transaction.date.formatted(.dateTime.month().day()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(transaction.amount.currencyExact)
                        .monospacedDigit()
                        .foregroundStyle(transaction.verdict == .leak ? Color(hex: "993C1D") : Color.primary)
                }
            }
        }
        .navigationTitle(categoryName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
