import SwiftUI
import SwiftData

/// How much, where it leaked, and what stood out — for a month, three months
/// or a year.
///
/// Design A with swipeable findings (D-023). The old screen led with a daily
/// chart that one rent payment flattened into a single spike, left its colours
/// unexplained, and phrased comparisons as "↗ 279%" and "7.6× a typical week".
/// This one answers "how much did I spend?" first, draws weeks or months rather
/// than days, and says what stood out in plain words.
///
/// Every row still navigates somewhere. Dead-end analytics is why people stop
/// opening these screens.
struct AnalysisView: View {

    @Query private var transactions: [Transaction]
    @Query private var profiles: [UserProfile]
    @State private var range: AnalysisAggregates.Range = .month

    /// Optional; 0 when not set, and then nothing mentions it (D-030).
    private var takeHome: Double { profiles.first?.monthlyTakeHome ?? 0 }

    /// Which page of the Chart / Findings card is showing. Remembered, so
    /// someone who prefers Findings opens straight onto it.
    @State private var page: Page? = .chart
    @AppStorage("analysis.page") private var savedPage = Page.chart.rawValue

    enum Page: String, Hashable { case chart, findings }

    private let brand = Color(hex: "C65A2E")
    private let worthIt = Color(hex: "1D9E75")
    private let worthItBar = Color(hex: "9FE1CB")

    // MARK: Derived

    private var headline: AnalysisSummary.Headline {
        AnalysisSummary.headline(transactions, range: range)
    }

    private var bars: [AnalysisSummary.Bar] {
        AnalysisSummary.bars(transactions, range: range)
    }

    private var findings: [AnalysisSummary.Finding] {
        AnalysisSummary.findings(transactions, range: range, takeHome: takeHome)
    }

    private var categories: [AnalysisAggregates.CategoryTotal] {
        AnalysisAggregates.categoryLeaks(transactions, range: range)
    }

    private var merchants: [AnalysisAggregates.MerchantTotal] {
        AnalysisAggregates.merchantLeaderboard(transactions, range: range)
    }

    private var hasData: Bool { headline.count > 0 }

    private var periodTitle: String {
        let interval = range.interval()
        switch range {
        case .month:
            return "Spent in \(interval.start.formatted(.dateTime.month(.wide)))"
        case .quarter:
            return "Spent in \(interval.start.formatted(.dateTime.month(.abbreviated))) – \(Date.now.formatted(.dateTime.month(.abbreviated)))"
        case .year:
            return "Spent in the last 12 months"
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    rangePicker
                        .scrollToTopAnchor()

                    if hasData {
                        headlineCard
                        pagerTabs
                        pager
                        pageDots
                        if !categories.isEmpty { categoryCard }
                        if !merchants.isEmpty { merchantCard }
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                .animation(.easeInOut(duration: 0.2), value: range)
            }
            .background(Color(.systemGroupedBackground))
            .scrollsToTopOnTabChange()
            .navigationTitle("Analysis")
            .navigationDestination(for: AnalysisAggregates.MerchantTotal.self) { merchant in
                MerchantDetailView(merchantName: merchant.merchant, range: range)
            }
            .navigationDestination(for: AnalysisAggregates.CategoryTotal.self) { category in
                CategoryDetailView(categoryName: category.name, range: range)
            }
            .onAppear { page = Page(rawValue: savedPage) ?? .chart }
            .onChange(of: page) { _, newValue in
                if let newValue { savedPage = newValue.rawValue }
            }
        }
    }

    // MARK: Card chrome

    private func card<Content: View>(
        minHeight: CGFloat = 0,
        fillsHeight: Bool = false,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(
                maxWidth: .infinity,
                minHeight: minHeight,
                maxHeight: fillsHeight ? .infinity : nil,
                alignment: .topLeading
            )
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(brand)
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

    // MARK: Headline

    /// The answer first: how much, how much of it leaked, and against what.
    private var headlineCard: some View {
        card {
            Text(periodTitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(headline.spent.currencyRounded)
                .font(.system(size: 36, weight: .semibold))
                .contentTransition(.numericText())
                .padding(.top, 2)

            splitBar
                .padding(.top, 9)

            (Text("\(headline.leaked.currencyRounded) leaked").fontWeight(.semibold).foregroundStyle(brand)
             + Text("  ·  ").foregroundStyle(Color(.tertiaryLabel))
             + Text("\(headline.kept.currencyRounded) worth it").foregroundStyle(worthIt))
                .font(.subheadline)
                .padding(.top, 7)

            if let context = headline.context {
                Text(context)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
            }

            // A quiet share, never a sentence — sentences live in Findings.
            if let share = TakeHome.headlineShare(
                spent: headline.spent,
                monthsWithSpending: range == .month ? 1 : bars.filter { $0.spent > 0 }.count,
                takeHome: takeHome
            ) {
                Text(share)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var splitBar: some View {
        let spent = max(headline.spent, 0.01)
        return GeometryReader { geometry in
            HStack(spacing: 2) {
                if headline.leaked > 0 {
                    Rectangle().fill(brand)
                        .frame(width: max(geometry.size.width * headline.leaked / spent - 2, 3))
                }
                if headline.kept > 0 {
                    Rectangle().fill(Color(hex: "5DCAA5"))
                        .frame(width: max(geometry.size.width * headline.kept / spent - 2, 3))
                }
                Spacer(minLength: 0)
            }
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    // MARK: Chart / Findings pager

    /// Labels above the card. Swiping is invisible on its own; the labels, the
    /// peeking edge of the next card and the dots are what make it findable.
    private var pagerTabs: some View {
        HStack(spacing: 22) {
            tab("Chart", .chart)
            tab("Findings", .findings)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func tab(_ title: String, _ target: Page) -> some View {
        let isOn = (page ?? .chart) == target
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { page = target }
        } label: {
            Text(title)
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? brand : Color.secondary)
                .padding(.bottom, 4)
                .overlay(alignment: .bottom) {
                    if isOn { Capsule().fill(brand).frame(height: 2) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Two cards side by side, snapping. Each takes 92% of the width so the
    /// next one's edge shows — the cue that there is a next one.
    ///
    /// A plain `HStack` with a fixed vertical size, so both cards are measured
    /// and both take the taller one's height. The lazy stack sized the row to
    /// the chart alone and cut the bottom off a longer Findings card.
    private var pager: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                chartCard
                    .containerRelativeFrame(.horizontal) { width, _ in width * 0.92 }
                    .id(Page.chart)
                findingsCard
                    .containerRelativeFrame(.horizontal) { width, _ in width * 0.92 }
                    .id(Page.findings)
            }
            .fixedSize(horizontal: false, vertical: true)
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $page)
        .scrollClipDisabled()
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach([Page.chart, Page.findings], id: \.self) { item in
                Capsule()
                    .fill((page ?? .chart) == item ? brand : Color(.systemGray4))
                    .frame(width: (page ?? .chart) == item ? 16 : 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: page)
        .accessibilityHidden(true)
    }

    // MARK: Chart

    /// The take-home line runs across monthly bars only; a weekly bar against
    /// a monthly figure would be guesswork.
    private var showsTakeHomeLine: Bool { takeHome > 0 && range != .month }

    private var chartCard: some View {
        let ceilingInfo = AnalysisSummary.chartCeiling(for: bars)
        // Room for the take-home line when it's drawn.
        let ceiling = showsTakeHomeLine ? max(ceilingInfo.ceiling, takeHome * 1.05) : ceilingInfo.ceiling
        let lineHeight: CGFloat? = showsTakeHomeLine ? 112 * takeHome / ceiling : nil
        let showValues = bars.count <= 6

        return card(minHeight: 236, fillsHeight: true) {
            sectionTitle(range == .month ? "Week by week" : "Month by month")

            if ceilingInfo.isCapped {
                Text("The tallest bar is cut off so the others stay readable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            // When Findings is the taller card, the extra room goes above the
            // bars, so they stay anchored to the legend at the bottom.
            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: bars.count > 6 ? 5 : 9) {
                ForEach(bars) { bar in
                    if range == .month && bar.spent > 0 {
                        // A week bar opens that week's purchases.
                        NavigationLink {
                            WeekDetailView(weekStart: bar.start, title: "Week of \(bar.label)")
                        } label: {
                            barColumn(bar, ceiling: ceiling, showValue: showValues, takeHomeHeight: lineHeight)
                        }
                        .buttonStyle(.plain)
                    } else {
                        barColumn(bar, ceiling: ceiling, showValue: showValues, takeHomeHeight: lineHeight)
                    }
                }
            }
            .frame(height: 150, alignment: .bottom)
            .padding(.top, 10)

            HStack(spacing: 14) {
                legend("Leaked", brand)
                legend("Worth it", worthItBar)
                if showsTakeHomeLine {
                    HStack(spacing: 5) {
                        DashedLine()
                            .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 2)
                        Text("Take-home")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    private func barColumn(
        _ bar: AnalysisSummary.Bar,
        ceiling: Double,
        showValue: Bool,
        takeHomeHeight: CGFloat? = nil
    ) -> some View {
        let plotHeight: CGFloat = 112
        let isCut = bar.spent > ceiling
        let shown = min(bar.spent, ceiling)
        let height = bar.spent > 0 ? max(plotHeight * shown / ceiling, 4) : 3
        let leakedHeight = bar.spent > 0 ? height * min(bar.leaked / bar.spent, 1) : 0

        return VStack(spacing: 4) {
            if showValue {
                Text(bar.spent > 0 ? compact(bar.spent) : "")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(bar.spent > 0 ? worthItBar : Color(.tertiarySystemFill))
                    .frame(height: height)
                if leakedHeight > 0 {
                    UnevenRoundedRectangle(
                        bottomLeadingRadius: 5,
                        bottomTrailingRadius: 5,
                        style: .continuous
                    )
                    .fill(brand)
                    .frame(height: leakedHeight)
                }
            }
            // A cut bar gets a break near its top, so it reads as "taller
            // than this" rather than as the real height.
            // The take-home line, drawn per column from the shared bottom
            // edge and stretched across the gaps so it reads as one line.
            .overlay(alignment: .bottom) {
                if let takeHomeHeight {
                    DashedLine()
                        .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                        .foregroundStyle(.secondary)
                        .frame(height: 2)
                        .padding(.horizontal, -5)
                        .offset(y: -takeHomeHeight)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) {
                if isCut {
                    Rectangle()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .frame(height: 3)
                        .rotationEffect(.degrees(-8))
                        .offset(y: 8)
                }
            }

            Text(bar.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bar.label): \(bar.spent.currencyRounded) spent, \(bar.leaked.currencyRounded) leaked")
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// "$820", "$1.7k" — the bar labels are glanceable, not accounting.
    private func compact(_ value: Double) -> String {
        guard value >= 1000 else { return value.currencyRounded }
        return (value / 1000).currency(code: AppSettings.currencyCode, fractionDigits: 1) + "k"
    }

    // MARK: Findings

    private var findingsCard: some View {
        let sorted = headline.count
        let threshold = AnalysisSummary.patternThreshold

        return card(minHeight: 236, fillsHeight: true) {
            sectionTitle("What stood out")

            if findings.isEmpty {
                Text("Nothing stands out yet. Findings appear as you sort purchases.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            } else {
                ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                    if index > 0 { Divider().padding(.leading, 32) }
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: finding.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(brand)
                            .frame(width: 22)
                        Text(markdown(finding.text))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                }
            }

            // Patterns wait for enough data, and say so rather than guessing.
            if sorted < threshold {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Habits like your most expensive day appear after \(threshold) sorted purchases.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView(value: Double(sorted), total: Double(threshold))
                        .tint(brand)
                    Text("\(sorted) of \(threshold)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 10)
            }
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }

    // MARK: Leak by category and merchant

    /// Ranked by leak, not spend — a grocery bill is the biggest line on any
    /// statement and almost never the answer to "what would I take back".
    private var categoryCard: some View {
        let maximum = categories.map(\.leaked).max() ?? 1

        return card {
            sectionTitle("Where it leaked")
                .padding(.bottom, 6)

            ForEach(categories) { category in
                NavigationLink(value: category) {
                    VStack(spacing: 5) {
                        HStack {
                            Text(category.name)
                                .font(.subheadline)
                            Spacer()
                            Text(category.leaked.currencyRounded)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.tertiarySystemFill))
                                Capsule()
                                    .fill(brand)
                                    .frame(width: max(geometry.size.width * (category.leaked / maximum), 4))
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var merchantCard: some View {
        card {
            sectionTitle("Leaked by shop")
                .padding(.bottom, 4)

            ForEach(Array(merchants.enumerated()), id: \.element.id) { index, merchant in
                if index > 0 { Divider() }
                NavigationLink(value: merchant) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(MerchantNormalizer.displayName(merchant.merchant))
                                .font(.subheadline)
                            Text("\(merchant.count) \(merchant.count == 1 ? "visit" : "visits")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(merchant.leaked.currencyRounded)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(brand)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing to analyse yet")
                .font(.headline)
            Text("Sort a few purchases and your spending shows up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// A horizontal line through the middle of its frame, for dashed strokes.
struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
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

extension AnalysisAggregates.WeekTotal: Hashable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.start == rhs.start }
    func hash(into hasher: inout Hasher) { hasher.combine(start) }
}

/// One week, every purchase in it.
///
/// Queried by date rather than handed the array, so edits made here are
/// reflected immediately instead of showing a snapshot taken when the
/// aggregate ran.
struct WeekDetailView: View {

    let weekStart: Date
    let title: String

    @Query(sort: \Transaction.date, order: .reverse)
    private var transactions: [Transaction]

    private var weekEnd: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
    }

    private var matching: [Transaction] {
        transactions.filter {
            $0.countsTowardTotals && $0.date >= weekStart && $0.date < weekEnd
        }
    }

    private var spent: Double { matching.reduce(0) { $0 + $1.amount } }
    private var leaked: Double {
        matching.filter { $0.verdict == .leak }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Spent", value: spent.currencyRounded)
                LabeledContent("Leaked", value: leaked.currencyRounded)
                LabeledContent("Purchases", value: "\(matching.count)")
            }

            Section("Every purchase") {
                ForEach(matching) { transaction in
                    NavigationLink {
                        TransactionDetailView(transaction: transaction)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(transaction.merchant.isEmpty ? "Unknown" : MerchantNormalizer.displayName(transaction.merchant))
                                    .font(.subheadline)
                                Text(transaction.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(transaction.amount.currencyExact)
                                .monospacedDigit()
                                .foregroundStyle(
                                    transaction.verdict == .leak
                                        ? Color(hex: "993C1D")
                                        : Color.primary
                                )
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
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
    /// A specific calendar month, when opened from Overview on a past month.
    /// Takes precedence over `range`, which always ends at today — without it,
    /// tapping Dining out in August showed September's dining.
    var month: Date? = nil

    @Query private var transactions: [Transaction]

    private var counted: [Transaction] {
        if let month, let interval = Calendar.current.dateInterval(of: .month, for: month) {
            return transactions.filter { $0.countsTowardTotals && interval.contains($0.date) }
        }
        return AnalysisAggregates.counted(transactions, in: range)
    }

    private var matching: [Transaction] {
        counted
            .filter { ($0.category?.name ?? "Uncategorised") == categoryName }
            .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        List {
            ForEach(matching) { transaction in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(transaction.merchant.isEmpty ? "Unknown" : MerchantNormalizer.displayName(transaction.merchant))
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
