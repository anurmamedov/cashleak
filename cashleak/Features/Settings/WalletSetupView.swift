import SwiftUI
import SwiftData

/// Whether Apple Pay capture is actually working, read from the capture log.
///
/// Three states, not two. The first real device test showed why: ten manual
/// runs of the shortcut filled the log, and a two-state check read that as
/// "working" while not one of them had come from a card tap. A real Wallet
/// capture always carries a merchant; a manual run, or an automation whose
/// Merchant field was never connected, never does. So a merchant is the test.
enum CaptureStatus: Equatable {
    /// Nothing has arrived.
    case notConnected
    /// Something arrives, but never with a merchant — almost always an
    /// unconnected field in the automation (step 5).
    case missingMerchant
    /// A real capture, merchant and all.
    case working(lastCapture: Date, merchant: String)
    /// It worked, then went quiet. An iOS update can rewrite or switch off the
    /// shortcut without a word — iOS 27 did — and one old capture would
    /// otherwise keep this green forever.
    case quiet(lastCapture: Date, merchant: String)

    /// After this long without a real capture, say so. Three days is short
    /// enough to catch a broken shortcut within a week, long enough that a
    /// weekend of paying cash isn't an alarm.
    static let quietAfter: TimeInterval = 3 * 86_400

    static func from(_ captures: [CaptureLogEntry], now: Date = .now) -> CaptureStatus {
        if let real = captures.first(where: { !$0.rawMerchant.isEmpty }) {
            return now.timeIntervalSince(real.receivedAt) > quietAfter
                ? .quiet(lastCapture: real.receivedAt, merchant: real.rawMerchant)
                : .working(lastCapture: real.receivedAt, merchant: real.rawMerchant)
        }
        return captures.isEmpty ? .notConnected : .missingMerchant
    }
}

/// The one-time setup that decides whether automatic capture works.
///
/// iOS reserves personal automations for the user: no API creates one, and an
/// app can't install one on their behalf. So this screen can't do the work — it
/// can only make the work impossible to get wrong. That means plain steps, one
/// idea each, and a picture of the step people actually miss: connecting Amount
/// and Merchant, where an unconnected field and a connected one look almost
/// identical unless you know what to look for.
struct WalletSetupView: View {

    @Query(sort: \CaptureLogEntry.receivedAt, order: .reverse)
    private var captures: [CaptureLogEntry]

    @Environment(\.openURL) private var openURL

    private let brand = Color(hex: "C65A2E")

    private var status: CaptureStatus { .from(captures) }

    /// A ready-made shortcut with Log transaction already connected to the
    /// payment (D-041). Installing it removes the search and both connections
    /// — the steps people get wrong. Shared from iCloud; swap the link here if
    /// the shortcut is ever re-shared.
    static let readyShortcutURL = URL(string: "https://www.icloud.com/shortcuts/8b1f2a1152124245a120e9f206e4c71c")!

    /// iOS 27 and later: the shortcut carries its own Wallet trigger, so
    /// installing it *is* the setup — apart from switching it on, which iOS
    /// leaves to the person.
    ///
    /// `nil` until a correct one is shared: the first iOS 27 link
    /// (6cabd9d0…) carried the trigger but no actions, so it would have logged
    /// nothing. Checked by decoding the shared file, October 7.
    static let readyShortcutWithTriggerURL: URL? = nil

    /// The link for this phone, or `nil` when there isn't a working one yet —
    /// then only the manual steps show.
    /// iOS 17 and 18 call the Wallet trigger "Transaction". Same trigger, same
    /// fields, older name. The app's floor is 17.6 (D-038).
    static var triggerName: String {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion <= 18 ? "Transaction" : "Wallet"
    }

    static var quickSetupURL: URL? {
        triggersTravelWithShortcut ? readyShortcutWithTriggerURL : readyShortcutURL
    }

    /// Read from the running OS rather than `#available`, so this compiles the
    /// same with any SDK.
    static var triggersTravelWithShortcut: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    private var isWorking: Bool {
        if case .working = status { return true }
        return false
    }

    var body: some View {
        List {
            Section {
                statusCard
                openShortcutsButton
            }
            .listRowSeparator(.hidden)

            if Self.quickSetupURL != nil { quickSetupSection }
            stepsSection
            coverageSection
            declineSection
        }
        .navigationTitle("Apple Pay capture")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Status

    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title2)
                .foregroundStyle(statusTint)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline.weight(.medium))
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var statusIcon: String {
        switch status {
        case .notConnected: "bolt.badge.clock"
        case .missingMerchant: "exclamationmark.triangle"
        case .working: "checkmark.circle.fill"
        case .quiet: "clock.badge.exclamationmark"
        }
    }

    private var statusTint: Color {
        switch status {
        case .notConnected: Color(hex: "854F0B")
        case .missingMerchant: Color(hex: "993C1D")
        case .working: Color(hex: "1D9E75")
        case .quiet: Color(hex: "C65A2E")
        }
    }

    private var statusTitle: String {
        switch status {
        case .notConnected: "Not connected yet"
        case .missingMerchant: "Merchant isn't coming through"
        case .working: "Working"
        case let .quiet(date, _): "Nothing since \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }

    private var statusDetail: String {
        switch status {
        case .notConnected:
            "Takes about two minutes, once."
        case .missingMerchant:
            "Captures are arriving without a shop name. Check step 5."
        case let .working(date, merchant):
            "Last capture \(date.formatted(.relative(presentation: .named))) at \(MerchantNormalizer.displayName(merchant))."
        case .quiet:
            "No Apple Pay purchase has come through for a few days. If you've paid with your phone since, an iOS update may have changed the shortcut — check it."
        }
    }

    // MARK: Open Shortcuts

    private var openShortcutsButton: some View {
        Button {
            // Opens the Shortcuts app. No URL can preselect the Automation
            // tab, which is why step 1 says where it is.
            if let url = URL(string: "shortcuts://") { openURL(url) }
        } label: {
            Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                .font(.body.weight(.medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(brand)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
    }

    // MARK: Steps

    /// One idea per step. Each title is the action; the line under it says
    /// where to find it or what to avoid. Anything longer gets skimmed, and a
    /// skimmed step is a skipped step.
    private var stepsSection: some View {
        Section {
            // Worded from a recording of the real iOS 26 flow (D-041).
            step(1, "Automation, then New Automation", "The tab at the bottom of Shortcuts. If you already have automations, tap + instead.")
            step(2, "Choose Wallet", "Every card and category comes ticked. Leave them all — one automation covers every card. On iOS 18 and earlier it's called Transaction.")
            step(3, "Scroll down, pick Run Immediately, then Next", "Not \"Run After Confirmation\" — that waits for you, so nothing happens on its own.")
            step(4, "Create New Shortcut, then add \"Log transaction\"", "Search CashLeak and pick Log transaction.")

            NavigationLink {
                ConnectFieldsView()
            } label: {
                step(5, "Connect Amount and Merchant", "The step most people miss. Tap to see how.", highlighted: true)
            }
            .listRowBackground(Color(hex: "854F0B").opacity(0.12))

            step(6, "Pay with your phone", "Something small, at a real till. The status above turns green. Pressing play in Shortcuts doesn't count — there's no payment behind it.")
        } header: {
            Text(Self.quickSetupURL == nil ? "Set it up" : (isWorking ? "Set it up by hand" : "Or set it up by hand"))
        }
    }

    // MARK: Quick setup

    /// The short way: install the ready-made shortcut, then point one
    /// automation at it. Still needs the person to create the automation —
    /// iOS doesn't let an app do that — but every step is a pick from a list.
    private var quickSetupSection: some View {
        Section {
            Button {
                if let url = Self.quickSetupURL { openURL(url) }
            } label: {
                Label(isWorking ? "Add Apple Pay capture again" : "Add Apple Pay capture", systemImage: "square.and.arrow.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isWorking ? brand : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(isWorking ? brand.opacity(0.12) : brand)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if !isWorking && Self.triggersTravelWithShortcut {
                step(1, "Tap Add Shortcut", "It arrives with the Wallet trigger and fields already set.")
                step(2, "Turn on Automation", "Open the shortcut and switch Automation on under \"When Any Card is tapped\". iOS leaves this one switch to you.")
                step(3, "Pay with your phone", "The status above turns green.")
            } else if !isWorking {
                step(1, "Tap Add Shortcut", "Shortcuts opens with it already connected.")
                step(2, "Automation, then New Automation", "If you already have automations, tap + instead.")
                step(3, "\(Self.triggerName) › scroll down › Run Immediately › Next", "Leave every card ticked.")
                step(4, "Pick the shortcut you just added", "Under My Shortcuts. That's it — no fields to connect.")
                step(5, "Pay with your phone", "The status above turns green.")
            }
        } header: {
            Text(isWorking ? "Something wrong?" : "Quickest way")
        } footer: {
            if isWorking {
                Text("If an iOS update or an edit changed the shortcut, add it again and point the automation at the new one.")
            }
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
        } header: {
            Text("What this captures")
        } footer: {
            Text("Recurring rules cover the predictable rest, and anything else takes five seconds to add by hand.")
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

    private func step(
        _ number: Int,
        _ title: String,
        _ detail: String,
        highlighted: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.medium))
                .frame(width: 24, height: 24)
                .background(highlighted ? Color(hex: "854F0B").opacity(0.2) : Color(.tertiarySystemFill))
                .foregroundStyle(highlighted ? Color(hex: "854F0B") : Color.primary)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(title). \(detail)")
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

// MARK: - Step 5

/// The step that broke the first real setup.
///
/// An unconnected field in Shortcuts is a faded blue word. A connected one is a
/// slightly brighter blue word with a small icon. Told in words, nobody can
/// tell those apart on their own screen — so this shows both, side by side,
/// and lets people match what they see.
struct ConnectFieldsView: View {

    var body: some View {
        List {
            Section {
                VStack(spacing: 4) {
                    Text("Connect Amount and Merchant")
                        .font(.title3.weight(.medium))
                        .multilineTextAlignment(.center)
                    Text("Look at the two blue words in your Log transaction action.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .listRowBackground(Color.clear)

            Section {
                example(connected: false)
            } header: {
                Label("Not connected", systemImage: "xmark")
                    .foregroundStyle(Color(hex: "A32D2D"))
            } footer: {
                Text("Faded words, no icon. Nothing will arrive — or Shortcuts will ask you to type the amount every time.")
            }

            Section {
                example(connected: true)
            } header: {
                Label("Connected", systemImage: "checkmark")
                    .foregroundStyle(Color(hex: "0F6E56"))
            } footer: {
                Text("Brighter words, each with a small icon. This works.")
            }

            Section {
                instruction("a", "Tap Amount", nil)
                instruction("b", "Tap Shortcut Input", "In the bar above the keyboard.")
                instruction("c", "Tap Shortcut Input again", "A list opens.")
                instruction("d", "Set Type to Transaction", "At the top of the list. Until you do, it only offers Text, File Size and so on — this is the step nobody guesses.")
                instruction("e", "Choose Amount", nil)
                instruction("f", "Do the same for Merchant", "Tap Merchant › Shortcut Input › tap it again › Type: Transaction › Merchant.")
            } header: {
                Text("How to connect each word")
            }

            Section {
                Text("Tap the arrow at the end of the action to show Details, then put Shortcut Input in it — as-is, without choosing anything. It sends everything Wallet knows about the payment, which helps us support more of it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Optional")
            }
        }
        .navigationTitle("Step 5 of 6")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A drawing of the Shortcuts action, close enough to match against the
    /// real one at a glance.
    private func example(connected: Bool) -> some View {
        HStack(spacing: 6) {
            // The real app icon, scaled down — the same picture Shortcuts puts
            // beside the action, so the drawing matches the phone.
            Image("ShortcutIcon")
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            Text("Log")
            pill("Amount", connected: connected)
            Text("at")
            pill("Merchant", connected: connected)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(connected
            ? "Log Amount at Merchant, both with an icon: connected"
            : "Log Amount at Merchant, faded with no icon: not connected")
    }

    private func pill(_ text: String, connected: Bool) -> some View {
        HStack(spacing: 3) {
            if connected {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption2)
            }
            Text(text)
        }
        .foregroundStyle(Color.blue.opacity(connected ? 1 : 0.45))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.blue.opacity(connected ? 0.18 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func instruction(_ letter: String, _ title: String, _ detail: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(letter)
                .font(.footnote.weight(.medium))
                .frame(width: 24, height: 24)
                .background(Color(.tertiarySystemFill))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
