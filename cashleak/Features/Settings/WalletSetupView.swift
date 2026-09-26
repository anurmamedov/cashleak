import SwiftUI
import SwiftData

/// The one-time setup that decides whether the product works.
///
/// iOS reserves personal automations for the user: no API creates one, and
/// unlike shortcuts they can't be shared or installed by an app. So this screen
/// can't do the work — but it can remove every bit of friction around it, and
/// it can tell the truth about whether it worked.
///
/// The live status at the top is the important part. Before this, someone could
/// follow eight steps, miss one, and find out days later that nothing had been
/// captured. Now the screen says so within seconds of the first tap.
struct WalletSetupView: View {

    @Query(sort: \CaptureLogEntry.receivedAt, order: .reverse)
    private var captures: [CaptureLogEntry]

    @Environment(\.openURL) private var openURL

    private var lastCapture: CaptureLogEntry? { captures.first }

    var body: some View {
        List {
            statusSection
            openShortcutsSection
            stepsSection
            coverageSection
            declineSection
        }
        .navigationTitle("Apple Pay")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Status

    /// Factual, not self-reported. Either something has arrived or it hasn't.
    private var statusSection: some View {
        Section {
            if let last = lastCapture {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color(hex: "1D9E75"))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("It's working")
                            .font(.subheadline.weight(.medium))
                        Text("Last capture \(last.receivedAt.formatted(.relative(presentation: .named))) — \(last.rawMerchant.isEmpty ? "no merchant" : last.rawMerchant)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "circle.dashed")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nothing captured yet")
                            .font(.subheadline.weight(.medium))
                        Text("Build the automation below, then tap-pay for something small. This turns green within seconds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        } footer: {
            Text("Apple doesn't let apps read your card activity, and a personal automation can't be installed for you — it's the one part you build yourself. It takes about a minute, once per card, and then every tap arrives on its own.")
        }
    }

    // MARK: Open Shortcuts

    private var openShortcutsSection: some View {
        Section {
            Button {
                // Deep-links straight into the Shortcuts app. It can't preselect
                // the Automation tab — no URL supports that — but it removes the
                // app-switching and searching.
                if let url = URL(string: "shortcuts://") {
                    openURL(url)
                }
            } label: {
                Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
            }
        } footer: {
            Text("Come back here afterwards and this screen will tell you whether it took.")
        }
    }

    // MARK: Steps

    private var stepsSection: some View {
        Section {
            step(1, "Automation tab, then +", "Bottom of the Shortcuts screen.")
            step(2, "Choose Wallet", "On iOS 25 and earlier it is called Transaction. Scroll — it is a long list.")
            step(3, "Select every card", "Tick all of them — one automation covers everything in Wallet.")
            step(4, "Run Immediately", "And turn Notify When Run off, or every purchase alerts you twice.")
            step(5, "Next, then New Blank Automation", "")
            step(6, "Search 'Log transaction'", "Pick the one from CashLeak.")
            step(7, "Fill Amount and Merchant", "Tap each field and choose the matching variable from the bar above the keyboard.")
            step(8, "Done", "Then buy a coffee and check back here.")
        } header: {
            Text("Build it")
        }
    }

    // MARK: Coverage

    private var coverageSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                row("Apple Pay from your phone or watch", captured: true)
                row("Physical card taps and chip-and-PIN", captured: false)
                row("In-app and web purchases", captured: false)
                row("E-transfers, pre-authorised debits, cash", captured: false)
            }
            .padding(.vertical, 2)

            Text("Roughly half of what you spend arrives on its own. Recurring rules cover the predictable rest, and anything else takes five seconds to add by hand.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("What this captures")
        }
    }

    private var declineSection: some View {
        Section {
            Text("A declined payment fires the automation too. It lands in Sort like anything else — swipe it away and it never reaches your totals.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Declines")
        }
    }

    // MARK: Rows

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.medium))
                .frame(width: 22, height: 22)
                .background(Color(.tertiarySystemFill))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func row(_ text: String, captured: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: captured ? "checkmark" : "xmark")
                .font(.caption.weight(.medium))
                .foregroundStyle(captured ? Color(hex: "1D9E75") : Color(hex: "993C1D"))
                .frame(width: 14)
            Text(text)
                .font(.subheadline)
        }
    }
}
