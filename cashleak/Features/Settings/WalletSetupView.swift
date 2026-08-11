import SwiftUI

/// The eight taps that decide whether the product works.
///
/// The App Intent is useless until the user builds a Shortcuts automation by
/// hand, once per card. This screen is not documentation — it's the feature.
/// Every step someone abandons here is a user for whom the app captures nothing
/// and who concludes it doesn't work.
///
/// It also states what won't be captured, up front. Discovering the gaps later
/// produces the worst review you can get.
struct WalletSetupView: View {

    var body: some View {
        List {
            Section {
                Text("Apple doesn't let apps read your card activity. Shortcuts does — you build one automation per card, and each tap gets sent here automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Set it up") {
                step(1, "Open Shortcuts", "The app that comes with iOS.")
                step(2, "Automation tab", "Bottom of the screen.")
                step(3, "Tap +, then Transaction", "Called Wallet on older versions of iOS.")
                step(4, "Pick a card", "The one you tap with most. Repeat later for others.")
                step(5, "Run Immediately", "Turn off Notify When Run, or you'll get two alerts per purchase.")
                step(6, "Next, then New Blank Automation", "")
                step(7, "Search 'Log transaction'", "Pick it from CashLeak.")
                step(8, "Set Amount and Merchant", "Tap each field and choose the matching Shortcut variable.")
            }

            Section {
                Label("Tap-pay for something small and check the Sort tab.", systemImage: "checkmark.circle")
                    .font(.subheadline)
            } header: {
                Text("Confirm it works")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    row("Apple Pay taps from your phone and watch", captured: true)
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

            Section {
                Text("A declined payment fires the automation too. It lands in Sort like anything else — swipe it away and it never reaches your totals.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Declines")
            }
        }
        .navigationTitle("Apple Pay")
        .navigationBarTitleDisplayMode(.inline)
    }

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
