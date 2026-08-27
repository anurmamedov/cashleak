import SwiftUI
import SwiftData

/// The screen that states the product thesis in its top third.
struct OverviewView: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var transactions: [Transaction]
    @Query private var goals: [Goal]

    private var summary: SpendingSummary {
        SpendingSummary.make(from: transactions)
    }

    private var leaksByCategory: [(category: Category?, total: Double)] {
        Array(SpendingSummary.leaksByCategory(from: transactions).prefix(4))
    }

    private var goal: Goal? {
        GoalStore.current(from: goals)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    leakCard
                    if let comparison = weekComparison { weekBanner(comparison) }
                    statsRow
                    if !leaksByCategory.isEmpty { leakBreakdown }
                    goalCard
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

        // The goal is what turns a number into a trade-off. Without one this
        // falls back to restating the ratio, which is honest but inert — hence
        // the prompt to set one.
        if let goal, let line = goal.tradeOffLine(leaked: summary.leaked) {
            return line
        }

        guard summary.leaked > 0 else {
            return "Nothing you'd take back this month."
        }

        let percent = Int((summary.leakRatio * 100).rounded())
        return "\(percent)% of what you spent this month."
    }

    // MARK: Week over week

    private var weekComparison: AnalysisAggregates.WeekComparison? {
        AnalysisAggregates.weekOverWeek(transactions)
    }

    /// The improvement line.
    ///
    /// A month figure blends a good week with a bad one and shows an
    /// unremarkable average. Someone who halved their leak on Tuesday should
    /// find that out, or there's no reward for the behaviour the whole app is
    /// trying to encourage. plan.md: "make it work in reverse".
    private func weekBanner(_ comparison: AnalysisAggregates.WeekComparison) -> some View {
        let improving = comparison.isImprovement
        let tint = improving ? Color(hex: "0F6E56") : Color(hex: "993C1D")

        return HStack(spacing: 10) {
            Image(systemName: improving ? "arrow.down.right" : "arrow.up.right")
                .font(.footnote.weight(.medium))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            Text(weekBannerText(comparison))
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// States the change and stops. No praise, no scolding — a number moved.
    private func weekBannerText(_ comparison: AnalysisAggregates.WeekComparison) -> String {
        let points = comparison.pointsChanged
        guard points >= 1 else { return "About the same as last week." }

        if comparison.isImprovement {
            let saved = comparison.lastWeekLeaked - comparison.thisWeekLeaked
            if saved > 0 {
                return "Down \(points) points from last week — \(saved.currencyRounded) less."
            }
            return "Down \(points) points from last week."
        }
        return "Up \(points) points from last week."
    }

    // MARK: Stats

    private var statsRow: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) { stats }
            } else {
                HStack(spacing: 10) { stats }
            }
        }
    }

    @ViewBuilder
    private var stats: some View {
            stat("Spent", summary.spent.currencyRounded, tint: .primary)

            // A month-end projection from three days of data is arithmetically
            // correct and practically alarming. Below a week, show what's known
            // instead of what's extrapolated.
            if summary.paceIsMeaningful {
                stat(
                    "On pace for",
                    summary.pace.currencyRounded,
                    tint: .primary,
                    footnote: "by month end"
                )
            } else {
                stat(
                    "Day",
                    "\(summary.daysElapsed)",
                    tint: .secondary,
                    footnote: "pace after a week"
                )
            }

            stat("Kept", summary.kept.currencyRounded, tint: Color(hex: "0F6E56"))
    }

    private func stat(
        _ label: String,
        _ value: String,
        tint: Color,
        footnote: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.title3.weight(.medium))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
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
                NavigationLink {
                    CategoryDetailView(
                        categoryName: row.category?.name ?? "Uncategorised",
                        range: .month
                    )
                } label: {
                    VStack(spacing: 5) {
                        HStack {
                            Text(row.category?.name ?? "Uncategorised")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(row.total.currencyRounded)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
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
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Goal

    @ViewBuilder
    private var goalCard: some View {
        if let goal {
            NavigationLink {
                GoalsView()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("\(goal.targetAmount.currencyRounded) · saving for")
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
            .buttonStyle(.plain)
        } else if summary.leaked > 0 {
            // The prompt only appears once there's a leak to compare against.
            // Asking on an empty month is asking before the question means
            // anything.
            NavigationLink {
                GoalsView()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("What would you rather have?")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Name something you're saving for")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color(hex: AppSettings.accentHex))
                }
                .padding(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
    }

}
