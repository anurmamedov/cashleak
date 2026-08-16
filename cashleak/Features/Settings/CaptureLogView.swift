import SwiftUI
import SwiftData

/// The L3 worksheet, inside the app.
///
/// Tap-pay a few times and this fills with exactly what the Wallet trigger
/// delivered — raw string, what the normalizer made of it, and what the ingest
/// funnel decided. Export produces Swift ready to paste into `TestSupport`.
///
/// The value is in the disagreements. A raw string that normalizes to something
/// wrong is a dedup bug waiting to happen, and it's invisible anywhere else.
struct CaptureLogView: View {

    @Environment(\.modelContext) private var context

    @Query(sort: \CaptureLogEntry.receivedAt, order: .reverse)
    private var entries: [CaptureLogEntry]

    @State private var exportText: String?

    private var distinctMerchants: Int {
        Set(entries.map(\.normalizedAtCapture).filter { !$0.isEmpty }).count
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Captured", value: "\(entries.count)")
                LabeledContent("Distinct merchants", value: "\(distinctMerchants)")

                if distinctMerchants < 10 {
                    Label(
                        "L3 wants 10 or more distinct merchants. \(10 - distinctMerchants) to go.",
                        systemImage: "circle.dashed"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } else {
                    Label("Enough to replace the guessed fixtures.", systemImage: "checkmark.circle")
                        .font(.footnote)
                        .foregroundStyle(Color(hex: "0F6E56"))
                }
            } footer: {
                Text("Every Apple Pay capture is recorded here verbatim, before anything interprets it. Repeat visits to the same shop are worth having — the question is whether the same shop sends the same string twice.")
            }

            if !entries.isEmpty {
                Section("What arrived") {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }

                Section {
                    Button {
                        exportText = CaptureLog.fixtureExport(entries)
                    } label: {
                        Label("Copy as test fixtures", systemImage: "doc.on.doc")
                    }

                    Button(role: .destructive) {
                        CaptureLog.clear(in: context)
                    } label: {
                        Label("Clear log", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Capture log")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            // An explicit closure rather than `.map(ExportPayload.init)`.
            // Passing the initializer as a function value strips it out of the
            // view's main-actor isolation, which Swift 6 warns about and will
            // eventually reject.
            get: { exportText.map { ExportPayload($0) } },
            set: { exportText = $0?.text }
        )) { payload in
            ShareSheet(items: [payload.text])
        }
    }

    private func row(_ entry: CaptureLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.rawMerchant.isEmpty ? "(no merchant)" : entry.rawMerchant)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(entry.rawMerchant.isEmpty ? .tertiary : .primary)
                Spacer()
                Text(entry.amount.currencyExact)
                    .font(.subheadline)
                    .monospacedDigit()
            }

            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(entry.normalizedAtCapture.isEmpty ? "(empty)" : entry.normalizedAtCapture)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(entry.outcome)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(outcomeTint(entry.outcome).opacity(0.15))
                    .foregroundStyle(outcomeTint(entry.outcome))
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(entry.receivedAt.formatted(date: .omitted, time: .standard))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }

    private func outcomeTint(_ outcome: String) -> Color {
        if outcome.hasPrefix("rejected") { return Color(hex: "993C1D") }
        if outcome == "duplicate" { return Color(hex: "854F0B") }
        return Color(hex: "0F6E56")
    }
}

private struct ExportPayload: Identifiable {
    let text: String
    var id: String { text }
    init(_ text: String) { self.text = text }
}
