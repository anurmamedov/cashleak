import SwiftUI
import SwiftData

/// Five slots: Overview · Sort · [Add] · Analysis · You
///
/// Native `TabView` so iOS picks up its own tab bar styling rather than us
/// reimplementing it. Add is a centre button that presents a sheet — it isn't a
/// destination, so it doesn't hold tab state.
///
/// Trips is deliberately absent. It's a card on Overview and a row in You;
/// used a few times a year, it doesn't earn permanent space. See D-006.
struct RootTabView: View {

    @Environment(\.modelContext) private var context
    @EnvironmentObject private var navigation: AppNavigation
    @State private var selection: Tab = .overview
    @State private var isAddPresented = false

    /// Bumped on every tab bar interaction so each tab returns to the top.
    /// See `ScrollToTop`.
    @State private var scrollToTopSignal = 0

    enum Tab: Hashable {
        case overview, sort, add, analysis, you
    }

    /// Unconfirmed count, shown as a badge on Sort.
    @Query(filter: #Predicate<Transaction> { !$0.isConfirmed && !$0.isSuperseded })
    private var unsorted: [Transaction]
    @Query private var widgetTransactions: [Transaction]

    var body: some View {
        TabView(selection: tabSelection) {
            OverviewView()
                .tabItem { Label("Overview", systemImage: "chart.pie") }
                .tag(Tab.overview)

            SortQueueView()
                .tabItem { Label("Sort", systemImage: "tray.full") }
                .badge(unsorted.count)
                .tag(Tab.sort)

            // Placeholder so the centre slot exists. Selecting it opens the
            // sheet and bounces selection back, so this view is never seen.
            Color.clear
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(Tab.add)

            AnalysisView()
                .tabItem { Label("Analysis", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.analysis)

            YouView()
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(Tab.you)
        }
        .environment(\.scrollToTopSignal, scrollToTopSignal)
        .sheet(isPresented: $isAddPresented) {
            AddTransactionSheet()
        }
        .task(id: unsorted.count) {
            await DailyReminderScheduler.refresh(in: context)
        }
        .task(id: widgetRevision) {
            WidgetSnapshotUpdater.refresh(from: widgetTransactions)
        }
        .onAppear(perform: followPendingRoute)
        .onChange(of: navigation.destination) { _, _ in
            followPendingRoute()
        }
    }

    /// Intercepts selection of the centre tab, presents the sheet, and restores
    /// the previous tab so Add never reads as a place you navigated to.
    private var tabSelection: Binding<Tab> {
        Binding(
            get: { selection },
            set: { newValue in
                if newValue == .add {
                    isAddPresented = true
                } else {
                    selection = newValue
                    // Outside the branch above deliberately: this fires when
                    // the current tab is tapped again as well as on a switch,
                    // which is what iOS does everywhere else. Add is excluded —
                    // it opens a sheet and isn't a destination.
                    scrollToTopSignal += 1
                }
            }
        )
    }

    private func followPendingRoute() {
        guard let destination = navigation.destination else { return }
        switch destination {
        case .sort:
            selection = .sort
        }
        navigation.consume(destination)
    }

    /// Includes every value the widget renders. A transaction edit that keeps
    /// the same row count must still publish a new snapshot.
    private var widgetRevision: Int {
        var hasher = Hasher()
        for transaction in widgetTransactions {
            hasher.combine(transaction.persistentModelID)
            hasher.combine(transaction.amount)
            hasher.combine(transaction.date)
            hasher.combine(transaction.isConfirmed)
            hasher.combine(transaction.isSuperseded)
        }
        hasher.combine(AppSettings.currencyCode)
        return hasher.finalize()
    }
}
