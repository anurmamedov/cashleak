import SwiftUI
import WidgetKit

struct CashLeakWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: CashLeakWidgetSnapshot
}

struct CashLeakWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CashLeakWidgetEntry {
        CashLeakWidgetEntry(
            date: .now,
            snapshot: CashLeakWidgetSnapshot(
                todaySpent: 48,
                unsortedCount: 2,
                currencyCode: "CAD",
                updatedAt: .now
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (CashLeakWidgetEntry) -> Void) {
        completion(CashLeakWidgetEntry(date: .now, snapshot: CashLeakWidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CashLeakWidgetEntry>) -> Void) {
        let now = Date.now
        let entry = CashLeakWidgetEntry(date: now, snapshot: CashLeakWidgetSnapshotStore.load())
        let nextMidnight = Calendar.current.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(3_600)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}

struct CashLeakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CashLeakWidgetEntry

    var body: some View {
        Group {
            if family == .systemMedium {
                medium
            } else {
                small
            }
        }
        .containerBackground(for: .widget) {
            Color(red: 0.98, green: 0.94, blue: 0.92)
        }
        .widgetURL(URL(string: "cashleak://sort"))
        .accessibilityElement(children: .combine)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("CashLeak", systemImage: "drop.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)

            Spacer(minLength: 2)

            Text("Today")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(todayAmount)
                .font(.title2.weight(.bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            unsortedLabel
        }
    }

    private var medium: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Label("CashLeak", systemImage: "drop.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Spacer()
                Text("Spent today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(todayAmount)
                    .font(.title.weight(.bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Text("Sort")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(entry.snapshot.unsortedCount)")
                    .font(.title.weight(.bold))
                Text(entry.snapshot.unsortedCount == 1 ? "purchase waiting" : "purchases waiting")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Text("Tap to review")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var unsortedLabel: some View {
        Text(entry.snapshot.unsortedCount == 0
             ? "All sorted"
             : "\(entry.snapshot.unsortedCount) to sort")
            .font(.caption.weight(.medium))
            .foregroundStyle(entry.snapshot.unsortedCount == 0 ? Color.secondary : accent)
    }

    private var todayAmount: String {
        entry.snapshot.todaySpent(at: entry.date).formatted(
            .currency(code: entry.snapshot.currencyCode).precision(.fractionLength(0))
        )
    }

    private var accent: Color {
        Color(red: 0.70, green: 0.20, blue: 0.08)
    }
}

struct CashLeakTodayWidget: Widget {
    let kind = "CashLeakTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CashLeakWidgetProvider()) { entry in
            CashLeakWidgetView(entry: entry)
        }
        .configurationDisplayName("Today’s spending")
        .description("See today’s total and what is waiting in Sort.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CashLeakWidgetBundle: WidgetBundle {
    var body: some Widget {
        CashLeakTodayWidget()
    }
}

#Preview(as: .systemSmall) {
    CashLeakTodayWidget()
} timeline: {
    CashLeakWidgetEntry(
        date: .now,
        snapshot: CashLeakWidgetSnapshot(
            todaySpent: 48,
            unsortedCount: 2,
            currencyCode: "CAD",
            updatedAt: .now
        )
    )
}
