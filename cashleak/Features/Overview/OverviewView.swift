import SwiftUI
import SwiftData

/// Where the money went — the month, today, and by category.
///
/// Design G3 (September 2026): white cards on a grouped background, with
/// CashLeak orange used only where it means something — leaks, today, the
/// section titles, the month arrows. It replaces a leaks-only screen on which
/// anything marked worth it simply vanished: fourteen coffees you were happy
/// with appeared nowhere. Now every purchase is visible somewhere, and the
/// verdict is carried inside each view rather than filtering it.
///
/// Shows one month at a time. Arrows in the title or a horizontal swipe move
/// through history. Things that only make sense for now — today, the
/// week-over-week line, the goal, the Sort reminder — appear only on the
/// current month.
struct OverviewView: View {

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var navigation: AppNavigation
    @ObservedObject private var sync = CloudSyncMonitor.shared
    @ObservedObject private var network = NetworkMonitor.shared

    @Query private var transactions: [Transaction]
    @Query private var goals: [Goal]
    @Query private var profiles: [UserProfile]

    @State private var selectedMonth = MonthNavigator.startOfMonth(.now)
    /// Set by pull-to-refresh, so the status line can say when it last checked
    /// even if no iCloud event was observed.
    @State private var lastChecked: Date?

    // MARK: Palette

    /// CashLeak orange, sampled from the logo. Reserved for leaks and for the
    /// few things that need a glance — today, section titles, month arrows.
    private let brand = Color(hex: "C65A2E")
    private let worthIt = Color(hex: "1D9E75")
    private let worthItBar = Color(hex: "5DCAA5")

    /// Added to the stack spacing above Today and the categories — roughly
    /// double the gap between cards that belong together.
    private let sectionGap: CGFloat = 14

    // MARK: Derived

    private var summary: SpendingSummary {
        SpendingSummary.make(from: transactions, month: selectedMonth)
    }

    private var categories: [SpendingSummary.CategorySpend] {
        SpendingSummary.byCategory(from: transactions, month: selectedMonth)
    }

    private var today: [Transaction] {
        SpendingSummary.purchases(on: .now, from: transactions)
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

    /// "this month" or "in August".
    private var monthPhrase: String {
        isCurrentMonth ? "this month" : "in \(monthName)"
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    syncStatus
                        .scrollToTopAnchor()
                    summaryCard
                    if isCurrentMonth, let comparison = weekComparison { weekBanner(comparison) }
                    if isCurrentMonth, unsortedCount > 0 { sortReminder }
                    // Wider gaps around Today so it reads as its own section,
                    // not a continuation of the month summary.
                    if isCurrentMonth {
                        todayCard
                            .padding(.top, sectionGap)
                    }
                    categoryCard
                        .padding(.top, sectionGap)
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
            .background(Color(.systemGroupedBackground))
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

    // MARK: Card chrome

    /// White in light mode, raised grey in dark — the system grouped pair, so
    /// dark mode needs nothing of its own.
    private func card<Content: View>(
        padding: CGFloat = 14,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(brand)
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
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(brand)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        // Faded rather than hidden: a vanishing arrow shifts the month name
        // sideways every time you reach an end.
        .opacity(target == nil ? 0.25 : 1)
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
                .foregroundStyle(brand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Sync status

    /// The line under the month: a status when there's something to know, a
    /// small greeting otherwise. "Up to date" is added only when it's known —
    /// an invented one would be worse than silence.
    @ViewBuilder
    private var syncStatus: some View {
        if let line = syncAlert {
            // Something to know about wins over the greeting.
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
            greetingLine
        }
    }

    /// "☀ Morning, Anar · ✓ up to date" — a small hello in the line that
    /// already exists, so it costs no space (D-032). After the first ten
    /// seconds the tick gives way to how long ago it updated (D-037).
    /// Re-evaluated every five seconds so "10 sec ago" moves on its own.
    private var greetingLine: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            let moment = Greeting.moment(at: timeline.date)
            let freshness = SyncFreshness.state(
                lastSync: lastSync,
                isOffline: network.isOffline,
                now: timeline.date
            )
            HStack(spacing: 5) {
                Image(systemName: moment.symbol)
                    .foregroundStyle(moment.isDaytime ? Color(hex: "BA7517") : Color(hex: "7F77DD"))
                Text(Greeting.text(for: moment, firstName: profiles.first?.firstName ?? ""))
                    .foregroundStyle(.secondary)
                if let freshness {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    switch freshness {
                    case .upToDate:
                        Image(systemName: "checkmark")
                            .foregroundStyle(worthIt)
                        Text("up to date")
                            .foregroundStyle(.secondary)
                    case .ago(let text):
                        Image(systemName: "clock")
                            .foregroundStyle(.tertiary)
                        Text(text)
                            .foregroundStyle(.secondary)
                    case .offline(let text):
                        Image(systemName: "wifi.slash")
                            .foregroundStyle(.tertiary)
                        Text(text)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    /// Something the person should know about the data — it takes the line.
    private var syncAlert: (icon: String, tint: Color, text: String)? {
        if sync.isImporting {
            let text = transactions.isEmpty
                ? "Restoring your data from iCloud. This can take a minute on a new install."
                : "Still syncing from iCloud · numbers may rise"
            return ("icloud.and.arrow.down", Color.secondary, text)
        }
        if sync.lastImportFailed {
            return ("exclamationmark.icloud", brand, "iCloud sync hit a problem · pull to try again")
        }
        return nil
    }

    /// The latest moment the data was known current: an iCloud import
    /// finished, or a pull checked. With neither, the greeting shows alone.
    private var lastSync: Date? {
        [sync.lastImportFinished, lastChecked].compactMap { $0 }.max()
    }

    // MARK: Summary

    /// The month in one card: what was spent, how much of it leaked, and the
    /// trade-off.
    ///
    /// Replaces the ratio-tinted leak card (D-020). Intensity still maps to
    /// ratio, never amount — it's now the width of the orange segment in the
    /// bar rather than the depth of a background colour.
    private var summaryCard: some View {
        card {
            Text(isCurrentMonth ? "Spent this month" : "Spent in \(monthName)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(summary.spent.currencyRounded)
                .font(.system(size: 40, weight: .semibold))
                .contentTransition(.numericText())
                .padding(.top, 2)

            splitBar
                .padding(.top, 10)

            HStack(spacing: 0) {
                Text("\(summary.leaked.currencyRounded) leaked")
                    .fontWeight(.semibold)
                    .foregroundStyle(brand)
                Text("  ·  ")
                    .foregroundStyle(.tertiary)
                Text("\(summary.kept.currencyRounded) worth it")
                    .foregroundStyle(worthIt)
            }
            .font(.subheadline)
            .padding(.top, 8)

            Text(summaryFootnote)
                .font(.footnote.italic())
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)

            if let line = takeHomeLine {
                takeHomeBlock(line)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Take-home

    /// Only when a take-home figure is set (D-030). A quiet number most of the
    /// time; one sentence only when something happened.
    private var takeHomeLine: TakeHome.OverviewLine? {
        let takeHome = profiles.first?.monthlyTakeHome ?? 0
        return TakeHome.overview(
            summary: summary,
            takeHome: takeHome,
            isCurrentMonth: isCurrentMonth,
            hasGoal: goal != nil,
            monthName: monthName,
            dayOfMonth: Calendar.current.component(.day, from: .now)
        )
    }

    private func takeHomeBlock(_ line: TakeHome.OverviewLine) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(line.barShare >= 1 ? brand : Color.primary.opacity(0.55))
                        .frame(width: max(geometry.size.width * line.barShare, 3))
                }
            }
            .frame(height: 5)

            if let sentence = line.sentence {
                Text(sentence)
                    .font(.footnote.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(line.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { Divider().offset(y: 2) }
        .accessibilityElement(children: .combine)
    }

    /// Leaked, worth it, and anything confirmed without a verdict, in that
    /// order. Widths are shares of what was spent, so they read as a ratio.
    private var splitBar: some View {
        let spent = summary.spent
        let unrated = max(spent - summary.leaked - summary.kept, 0)

        return GeometryReader { geometry in
            HStack(spacing: 2) {
                if spent > 0 {
                    segment(summary.leaked / spent, width: geometry.size.width, color: brand)
                    segment(summary.kept / spent, width: geometry.size.width, color: worthItBar)
                    segment(unrated / spent, width: geometry.size.width, color: Color(.systemGray4))
                }
                Spacer(minLength: 0)
            }
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
        }
        .frame(height: 9)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func segment(_ share: Double, width: CGFloat, color: Color) -> some View {
        if share > 0 {
            Rectangle()
                .fill(color)
                .frame(width: max(width * share - 2, 3))
        }
    }

    /// The trade-off, then pace. States the number and stops; never scolds.
    private var summaryFootnote: String {
        guard summary.transactionCount > 0 else {
            return isCurrentMonth
                ? "Nothing sorted yet this month."
                : "Nothing sorted in \(monthName)."
        }

        let tradeOff: String
        if isCurrentMonth, let goal, let line = goal.tradeOffLine(leaked: summary.leaked) {
            tradeOff = line.hasSuffix(".") ? String(line.dropLast()) : line
        } else if summary.leaked > 0 {
            tradeOff = "\(Int((summary.leakRatio * 100).rounded()))% of what you spent \(monthPhrase)"
        } else {
            tradeOff = "Nothing you'd take back \(monthPhrase)"
        }

        if isCurrentMonth {
            let pace = summary.paceIsMeaningful
                ? "on pace for \(summary.pace.currencyRounded)"
                : "on pace for \(summary.pace.currencyRounded), roughly — only \(summary.daysElapsed) day\(summary.daysElapsed == 1 ? "" : "s") in"
            return "\(tradeOff) · \(pace)"
        }
        return "\(tradeOff) · \(summary.perDay.currencyRounded) a day"
    }

    // MARK: Week over week

    private var weekComparison: AnalysisAggregates.WeekComparison? {
        AnalysisAggregates.weekOverWeek(transactions)
    }

    /// A month figure blends a good week with a bad one. Someone who halved
    /// their leak on Tuesday should find that out. plan.md: "make it work in
    /// reverse".
    private func weekBanner(_ comparison: AnalysisAggregates.WeekComparison) -> some View {
        let improving = comparison.isImprovement
        let tint = improving ? worthIt : brand

        return HStack(spacing: 10) {
            Image(systemName: improving ? "arrow.down.right" : "arrow.up.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14))
                .clipShape(Circle())

            Text(weekBannerText(comparison))
                .font(.subheadline)

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

    // MARK: Sort reminder

    /// Says where a new payment went. Without this, paying and then opening
    /// Overview looks exactly like the app not updating.
    private var sortReminder: some View {
        Button {
            navigation.destination = .sort
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "tray.full")
                Text("\(unsortedCount) in Sort, not counted yet")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .font(.subheadline)
            .foregroundStyle(Color(hex: "993C1D"))
            .padding(13)
            .background(brand.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Today

    /// What was bought today, sorted or not — its own section, set apart from
    /// the month above it.
    ///
    /// Includes captures still in Sort, marked "To sort". The question this card
    /// answers is "did my coffee register?", and hiding an unsorted one would
    /// answer it wrongly. The leaked and worth-it figures count only what has
    /// been sorted, the same rule as every total in the app.
    private var todayCard: some View {
        let total = today.reduce(0) { $0 + $1.amount }
        let sorted = today.filter(\.isConfirmed)
        let leaked = sorted.filter { $0.verdict == .leak }.reduce(0) { $0 + $1.amount }
        let worth = sorted.filter { $0.verdict == .worthIt }.reduce(0) { $0 + $1.amount }
        let limit = 8

        return card(padding: 16) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle("Today")
                Spacer()
                Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(total.currencyExact)
                .font(.system(size: 30, weight: .semibold))
                .contentTransition(.numericText())
                .padding(.top, 4)

            todaySummaryLine(count: today.count, leaked: leaked, worth: worth)
                .padding(.top, 2)

            Divider()
                .padding(.top, 12)
                .padding(.bottom, 2)

            if today.isEmpty {
                Text("Nothing yet today. Payments you tap with your phone appear here within seconds.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(today.prefix(limit).enumerated()), id: \.element.persistentModelID) { index, transaction in
                    if index > 0 { Divider().padding(.leading, 52) }
                    NavigationLink {
                        TransactionDetailView(transaction: transaction)
                    } label: {
                        purchaseRow(transaction)
                    }
                    .buttonStyle(.plain)
                }
                if today.count > limit {
                    Text("\(today.count - limit) more today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }

            NavigationLink {
                HistoryView()
            } label: {
                HStack(spacing: 4) {
                    Text("See other days")
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(brand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(brand.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
    }

    /// "4 purchases · $6.25 leaked · $47.95 worth it". Parts with nothing in
    /// them are left out rather than shown as $0.00.
    private func todaySummaryLine(count: Int, leaked: Double, worth: Double) -> some View {
        var parts: [Text] = [
            Text("\(count) purchase\(count == 1 ? "" : "s")").foregroundStyle(.secondary)
        ]
        if leaked > 0 {
            parts.append(Text("\(leaked.currencyExact) leaked").fontWeight(.semibold).foregroundStyle(brand))
        }
        if worth > 0 {
            parts.append(Text("\(worth.currencyExact) worth it").foregroundStyle(worthIt))
        }

        let separator = Text("  ·  ").foregroundStyle(Color(.tertiaryLabel))
        let line = parts.dropFirst().reduce(parts[0]) { $0 + separator + $1 }
        return line
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func purchaseRow(_ transaction: Transaction) -> some View {
        HStack(spacing: 12) {
            categoryIcon(transaction.category, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.merchant.isEmpty ? "Unknown" : MerchantNormalizer.displayName(transaction.merchant))
                    .font(.body)
                    .lineLimit(1)
                Text(transaction.date.formatted(date: .omitted, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text(transaction.amount.currencyExact)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                verdictPill(transaction)
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Solid orange for a leak, solid green for worth it, grey for a capture
    /// nobody has judged yet.
    private func verdictPill(_ transaction: Transaction) -> some View {
        let (text, fill): (String, Color) = {
            guard transaction.isConfirmed else { return ("To sort", Color(.systemGray)) }
            switch transaction.verdict {
            case .leak: return ("Leak", brand)
            case .worthIt: return ("Worth it", worthIt)
            case .unrated: return ("Sorted", Color(.systemGray))
            }
        }()

        return Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(fill)
            .clipShape(Capsule())
    }

    // MARK: Categories

    /// Every category's spending for the selected month — not just leaks.
    ///
    /// The title stays fixed and the line under it names the period: "This
    /// month · …" or "August · …". Under "Today" an unlabelled list read as
    /// today's categories, and a title with "this month" in it would be wrong
    /// the moment you switch to August.
    private var categoryCard: some View {
        let rows = categories
        let shown = Array(rows.prefix(6))
        let maximum = rows.map(\.total).max() ?? 1
        let period = isCurrentMonth ? "This month" : monthName

        return card {
            sectionTitle("Spending by category")
            Text(rows.isEmpty
                 ? "\(period) · sorted purchases appear here."
                 : "\(period) · \(summary.spent.currencyRounded) across \(rows.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .padding(.bottom, rows.isEmpty ? 0 : 8)

            ForEach(shown) { row in
                NavigationLink {
                    CategoryDetailView(categoryName: row.name, range: .month, month: selectedMonth)
                } label: {
                    categoryRow(row, maximum: maximum)
                }
                .buttonStyle(.plain)
            }

            if rows.count > shown.count {
                let rest = rows.dropFirst(shown.count)
                let restTotal = rest.reduce(0) { $0 + $1.total }
                NavigationLink {
                    AllCategoriesView(rows: rows, month: selectedMonth, monthName: monthName)
                } label: {
                    HStack {
                        Text("\(rest.count) more · \(restTotal.currencyRounded)")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(brand)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
    }

    private func categoryRow(_ row: SpendingSummary.CategorySpend, maximum: Double) -> some View {
        let tint = Color(hex: row.category?.colorHex ?? "888780")

        return HStack(spacing: 11) {
            categoryIcon(row.category, size: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(row.name)
                        .font(.subheadline)
                    Spacer()
                    Text(row.total.currencyRounded)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }

                GeometryReader { geometry in
                    let full = geometry.size.width * (row.total / maximum)
                    let leaked = geometry.size.width * (row.leaked / maximum)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.tertiarySystemFill))
                        Capsule().fill(tint.opacity(0.45)).frame(width: max(full, 4))
                        if row.leaked > 0 {
                            Capsule().fill(brand).frame(width: max(leaked, 4))
                        }
                    }
                }
                .frame(height: 6)

                if row.leaked > 0 {
                    Text("\(row.leaked.currencyRounded) leaked · \(row.count) purchase\(row.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(brand)
                } else {
                    Text("\(row.count) purchase\(row.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The category's own symbol on a pale wash of its own colour. Uncategorised
    /// gets a neutral question mark — it's a prompt, not a category.
    private func categoryIcon(_ category: Category?, size: CGFloat) -> some View {
        let tint = Color(hex: category?.colorHex ?? "888780")
        return Image(systemName: category?.icon ?? "questionmark")
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }

    // MARK: Goal

    @ViewBuilder
    private var goalCard: some View {
        if let goal {
            NavigationLink {
                GoalsView()
            } label: {
                HStack {
                    Image(systemName: "target")
                        .foregroundStyle(brand)
                        .frame(width: 32, height: 32)
                        .background(brand.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.name)
                            .font(.subheadline.weight(.medium))
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
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        } else if summary.leaked > 0 {
            // Only once there's a leak to compare against. Asking on an empty
            // month is asking before the question means anything.
            NavigationLink {
                GoalsView()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("What would you rather have?")
                            .font(.subheadline.weight(.medium))
                        Text("Name something you're saving for")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(brand)
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - All categories

/// Every category for a month, when there are more than fit on Overview.
struct AllCategoriesView: View {

    let rows: [SpendingSummary.CategorySpend]
    let month: Date
    let monthName: String

    var body: some View {
        List(rows) { row in
            NavigationLink {
                CategoryDetailView(categoryName: row.name, range: .month, month: month)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                        if row.leaked > 0 {
                            Text("\(row.leaked.currencyRounded) leaked")
                                .font(.caption)
                                .foregroundStyle(Color(hex: "C65A2E"))
                        }
                    }
                    Spacer()
                    Text(row.total.currencyRounded)
                        .monospacedDigit()
                }
            }
        }
        .navigationTitle("\(monthName) spending")
        .navigationBarTitleDisplayMode(.inline)
    }
}
