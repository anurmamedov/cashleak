import SwiftUI
import SwiftData

/// The screen that states the product thesis in its top third.
///
/// Shows one month at a time. The current month by default; arrows or a
/// horizontal swipe move back through history. Everything on the page — the
/// leak card, the stats, the category breakdown and where its rows lead —
/// follows the selected month. Things that only make sense for *now* (the
/// week-over-week line, the goal, the Sort reminder) appear only on the
/// current month.
struct OverviewView: View {

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var navigation: AppNavigation
    @ObservedObject private var sync = CloudSyncMonitor.shared

    @Query private var transactions: [Transaction]
    @Query private var goals: [Goal]

    @State private var selectedMonth = MonthNavigator.startOfMonth(.now)
    /// Set by pull-to-refresh, so the status line can say when it last checked
    /// even if no iCloud event was observed.
    @State private var lastChecked: Date?

    // MARK: Derived

    private var summary: SpendingSummary {
        SpendingSummary.make(from: transactions, month: selectedMonth)
    }

    private var leaksByCategory: [(category: Category?, total: Double)] {
        Array(SpendingSummary.leaksByCategory(from: transactions, month: selectedMonth).prefix(4))
    }

    private var goal: Goal? {
        GoalStore.current(from: goals)
    }

    private var months: [Date] {
        MonthNavigator.availableMonths(
            from: transactions.filter(\.countsTowardTotals).map(\.date)
        )
    }

    private var isCurrentMonth: Bool {
        MonthNavigator.isCurrent(selectedMonth)
    }

    private var previousMonth: Date? {
        MonthNavigator.previous(before: selectedMonth, in: months)
    }

    private var nextMonth: Date? {
        MonthNavigator.next(after: selectedMonth, in: months)
    }

    /// Captures waiting in Sort. Not in any total until sorted — which is the
    /// most common reason Overview looks like it hasn't updated.
    private var unsortedCount: Int {
        transactions.filter(\.needsSorting).count
    }

    private var monthName: String {
        selectedMonth.formatted(.dateTime.month(.wide))
    }

    /// "this month" or "in August" — the leak card and trade-off line say
    /// which month they mean.
    private var monthPhrase: String {
        isCurrentMonth ? "this month" : "in \(monthName)"
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    syncStatus
                        .scrollToTopAnchor()
                    leakCard
                    if isCurrentMonth, let comparison = weekComparison { weekBanner(comparison) }
                    statsRow
                    if isCurrentMonth, unsortedCount > 0 { sortReminder }
                    if !leaksByCategory.isEmpty { leakBreakdown }
                    if isCurrentMonth {
                        goalCard
                    } else {
                        backToCurrentButton
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                .animation(.easeInOut(duration: 0.25), value: selectedMonth)
            }
            .scrollsToTopOnTabChange()
            // Horizontal swipe changes month. Simultaneous, and only acted on
            // when clearly sideways, so vertical scrolling is never hijacked.
            .simultaneousGesture(monthSwipe)
            .refreshable {
                await AppRefresh.catchUp(in: context)
                lastChecked = .now
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { monthHeader }
            }
            .onChange(of: months.count) { _, _ in
                // History can shrink (a deleted transaction, a reset) and leave
                // the selection pointing at a month that no longer exists.
                if MonthNavigator.index(of: selectedMonth, in: months) == nil {
                    selectedMonth = MonthNavigator.startOfMonth(.now)
                }
            }
        }
    }

    // MARK: Month header

    private var monthHeader: some View {
        HStack(spacing: 14) {
            monthArrow("chevron.left", label: "Previous month", target: previousMonth)

            VStack(spacing: 1) {
                Text(monthName)
                    .font(.headline)
                Text(isCurrentMonth ? "This month" : "Final")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 110)
            .accessibilityElement(children: .combine)

            monthArrow("chevron.right", label: "Next month", target: nextMonth)
        }
    }

    private func monthArrow(_ symbol: String, label: String, target: Date?) -> some View {
        Button {
            if let target { select(target) }
        } label: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(Color(.tertiarySystemFill))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        // Greyed rather than hidden: a vanishing arrow shifts the month name
        // sideways every time you reach an end.
        .opacity(target == nil ? 0.3 : 1)
        .disabled(target == nil)
        .accessibilityLabel(label)
    }

    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                // Swipe left moves forward in time, as in Calendar and Photos.
                if dx < 0, let next = nextMonth {
                    select(next)
                } else if dx > 0, let previous = previousMonth {
                    select(previous)
                }
            }
    }

    private func select(_ month: Date) {
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedMonth = MonthNavigator.startOfMonth(month)
        }
    }

    private var backToCurrentButton: some View {
        Button {
            select(.now)
        } label: {
            Label("Back to \(Date.now.formatted(.dateTime.month(.wide)))", systemImage: "arrow.uturn.backward")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Sync status

    /// Says whether the numbers below are complete.
    ///
    /// Hidden entirely when nothing is known — no iCloud event seen and no
    /// manual refresh. An invented "up to date" would be worse than silence.
    @ViewBuilder
    private var syncStatus: some View {
        if let line = syncLine {
            HStack(spacing: 5) {
                Image(systemName: line.icon)
                    .foregroundStyle(line.tint)
                Text(line.text)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        } else {
            // Keeps a stable anchor for scroll-to-top when there's no line.
            Color.clear.frame(height: 0)
        }
    }

    private var syncLine: (icon: String, tint: Color, text: String)? {
        if sync.isImporting {
            let text = transactions.isEmpty
                ? "Restoring your data from iCloud. This can take a minute on a new install."
                : "Still syncing from iCloud · numbers may rise"
            return ("icloud.and.arrow.down", Color.secondary, text)
        }
        if sync.lastImportFailed {
            return ("exclamationmark.icloud", Color(hex: "993C1D"), "iCloud sync hit a problem · pull to try again")
        }
        let checked = [sync.lastImportFinished, lastChecked].compactMap { $0 }.max()
        if let checked {
            return ("checkmark", Color(hex: "1D9E75"),
                    "Up to date · \(checked.formatted(.relative(presentation: .named)))")
        }
        return nil
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
        let foreground = LeakRamp.foreground(
            ratio: ratio,
            transactionCount: summary.transactionCount,
            daysOfHistory: summary.daysOfHistory,
            colorScheme: colorScheme
        )

        return VStack(alignment: .leading, spacing: 8) {
            Text(isCurrentMonth ? "Leaked this month" : "Leaked in \(monthName)")
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
        .accessibilityLabel("Leaked \(monthPhrase), \(summary.leaked.currencyRounded). \(tradeOffLine)")
    }

    /// States the number and the trade-off, then stops. Never scolds.
    private var tradeOffLine: String {
        guard summary.transactionCount > 0 else {
            return isCurrentMonth ? "Nothing sorted yet this month." : "Nothing sorted in \(monthName)."
        }

        // The goal is what turns a number into a trade-off — but it's today's
        // goal, so it only speaks for today's month.
        if isCurrentMonth, let goal, let line = goal.tradeOffLine(leaked: summary.leaked) {
            return line
        }

        guard summary.leaked > 0 else {
            return "Nothing you'd take back \(monthPhrase)."
        }

        let percent = Int((summary.leakRatio * 100).rounded())
        return "\(percent)% of what you spent \(monthPhrase)."
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
                HStack(alignment: .top, spacing: 10) { stats }
            }
        }
    }

    /// Always three real numbers, each with one line saying what it is.
    ///
    /// Pace used to be replaced by "Day 3" for the first week, because an
    /// early projection can look alarming. Showing no number read as broken
    /// instead, so the number stays and its caption carries the caveat.
    @ViewBuilder
    private var stats: some View {
        stat("Spent", summary.spent.currencyRounded, tint: Color.primary,
             caption: isCurrentMonth ? "Everything you sorted" : "The whole month")

        if isCurrentMonth {
            stat("On pace", summary.pace.currencyRounded, tint: Color.primary, caption: paceCaption)
        } else {
            stat("Per day", summary.perDay.currencyRounded, tint: Color.primary,
                 caption: "Average over \(summary.daysElapsed) days")
        }

        stat("Kept", summary.kept.currencyRounded, tint: Color(hex: "0F6E56"),
             caption: "Marked worth it")
    }

    private var paceCaption: String {
        guard summary.spent > 0 else { return "Sort a purchase to start" }
        if summary.paceIsMeaningful {
            let last = MonthNavigator.lastDay(of: selectedMonth)
            return "By \(last.formatted(.dateTime.month(.abbreviated).day())) at this rate"
        }
        let days = summary.daysElapsed
        return "Rough — only \(days) day\(days == 1 ? "" : "s") in"
    }

    private func stat(_ label: String, _ value: String, tint: Color, caption: String) -> some View {
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
                .contentTransition(.numericText())
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Sort reminder

    /// Says where a new payment went. Without this, paying and then opening
    /// Overview looks exactly like the app not updating.
    private var sortReminder: some View {
        Button {
            navigation.destination = .sort
        } label: {
            HStack {
                Label(
                    "\(unsortedCount) in Sort, not counted yet",
                    systemImage: "tray.full"
                )
                .font(.subheadline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(Color(hex: "854F0B"))
            .padding(12)
            .background(Color(hex: "854F0B").opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
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
                        range: .month,
                        month: selectedMonth
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
