import AppIntents
import SwiftData
import Foundation

/// The Apple Pay capture path.
///
/// There is no API that reads Apple Pay transactions. `PassKit` only *accepts*
/// payments; `FinanceKit` is US and UK only, entitlement-gated, and requires a
/// Finance category listing. What exists instead is the Shortcuts **Wallet
/// automation trigger**: the user creates a personal automation on a card, and
/// Shortcuts hands `Amount` and `Merchant` to this intent when they tap to pay.
///
/// Consequences that shape the implementation:
///
/// - `openAppWhenRun = false`. Bringing the app forward while someone is
///   standing at a terminal is unacceptable.
/// - The trigger fires on **declined** transactions. Nothing distinguishes a
///   decline from a purchase in the payload, so everything lands unconfirmed
///   and the user drops it with a swipe.
/// - Delivery can lag when the issuer is slow, which is why dedup uses a
///   72-hour window rather than minutes.
/// - The user must build the automation by hand, once per card. See
///   `WalletSetupView` — an intent nobody wires up captures nothing.
struct LogWalletTransaction: AppIntent {

    static var title: LocalizedStringResource = "Log transaction"

    // ITMS-90626 rejects an App Intent description containing "Apple", so this
    // says "card tap" instead of "Apple Pay transaction". The wording is the
    // only thing that changed — this is still the Wallet capture path.
    static var description = IntentDescription(
        "Records a card tap in CashLeak. It arrives unconfirmed, ready to sort.",
        categoryName: "Capture"
    )

    /// Never bring the UI forward — this runs mid-checkout.
    static var openAppWhenRun: Bool = false

    /// Text, not `Double`, and that is deliberate.
    ///
    /// The Wallet trigger hands `Amount` over as text — `$7.29`, currency
    /// symbol included — and Shortcuts will not coerce that to a number. A
    /// `Double` parameter makes every single capture fail with "couldn't
    /// convert from Text to Number", which is exactly what happened on the
    /// first real device: automation correct, trigger firing, intent called,
    /// nothing captured. Taking text and parsing it here is the only way the
    /// value survives the handoff.
    @Parameter(title: "Amount")
    var amount: String

    @Parameter(title: "Merchant")
    var merchant: String?

    /// Optional so the automation can pass the transaction's own timestamp when
    /// Shortcuts provides one. Defaults to now.
    @Parameter(title: "Date")
    var date: Date?

    /// A catch-all for the rest of the payload, and a temporary one.
    ///
    /// Apple documents neither the Wallet trigger's variables nor their
    /// formats. We read Amount and Merchant because those two are visibly
    /// offered; whether the payload also carries the card, a transaction type,
    /// its own timestamp or a merchant category is unknown, and guessing at an
    /// undocumented payload is exactly what produced the first three L3
    /// findings.
    ///
    /// So `WalletSetupView` asks the user to drop every remaining variable
    /// Shortcuts offers into this one field. Nothing parses it — it lands in the
    /// capture log verbatim and gets read. When the payload is known, the fields
    /// worth having become named parameters and this is removed.
    ///
    /// Optional, so an automation built before this existed keeps working.
    @Parameter(title: "Details")
    var details: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant)")
    }

    /// Pulls a number out of whatever the trigger sent.
    ///
    /// Handles the shapes seen in the wild and the plausible neighbours:
    /// `$7.29`, `7.29`, `CA$7.29`, `US$1,234.56`, `7,29` (comma decimal),
    /// `-7.29`, and stray whitespace or non-breaking spaces. Returns 0 when
    /// there is no number at all, which `TransactionIngest` already rejects as
    /// a non-positive amount rather than storing nonsense.
    static func parseAmount(_ raw: String) -> Double {
        let kept = raw.filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }
        guard !kept.isEmpty else { return 0 }

        let lastDot = kept.lastIndex(of: ".")
        let lastComma = kept.lastIndex(of: ",")

        let normalized: String
        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            // Both present: the rightmost is the decimal separator and the
            // other is a thousands separator. "1,234.56" and "1.234,56".
            if dot > comma {
                normalized = kept.replacingOccurrences(of: ",", with: "")
            } else {
                normalized = kept
                    .replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: ".")
            }
        case (nil, .some):
            // A lone comma is a decimal separator in most of the world, but a
            // thousands separator in "1,234". Two digits after it means cents.
            let tail = kept.split(separator: ",").last.map(String.init) ?? ""
            normalized = tail.count == 2
                ? kept.replacingOccurrences(of: ",", with: ".")
                : kept.replacingOccurrences(of: ",", with: "")
        default:
            normalized = kept
        }

        return Double(normalized) ?? 0
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppModelContainer.shared.mainContext

        let parsedAmount = Self.parseAmount(amount)

        let result = TransactionIngest.ingest(
            amount: parsedAmount,
            merchant: merchant,
            date: date ?? .now,
            source: .applePay,
            into: context
        )

        // Record what actually arrived, before anything interpreted it.
        // This is L3's data collection — see `CaptureLogEntry`.
        CaptureLog.record(
            rawMerchant: merchant,
            amount: parsedAmount,
            source: .applePay,
            outcome: {
                switch result {
                case .inserted: "inserted"
                case .duplicate: "duplicate"
                case .rejected(let reason): "rejected: \(reason.rawValue)"
                }
            }(),
            rawDetails: details,
            in: context
        )
        await DailyReminderScheduler.refresh(in: context)
        WidgetSnapshotUpdater.refresh(in: context)

        // Dialog text is deliberately terse. It can surface as a banner while
        // the user is still at the till, so it states the outcome and stops.
        switch result {
        case .inserted:
            // The parsed value, not the raw text — `amount` is now whatever
            // Wallet sent, symbol and all.
            return .result(dialog: "Logged \(parsedAmount.currencyExact)")
        case .duplicate:
            return .result(dialog: "Already had that one")
        case .rejected:
            // A decline or a bad parse. Say nothing useful and record nothing —
            // an error here would train the user to distrust the automation.
            return .result(dialog: "Nothing to log")
        }
    }
}

/// Makes the intent discoverable in Shortcuts and by voice without the user
/// having to search for it.
struct CashLeakShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWalletTransaction(),
            phrases: [
                "Log a transaction in \(.applicationName)",
                "Add spending to \(.applicationName)",
            ],
            shortTitle: "Log transaction",
            systemImageName: "creditcard"
        )
    }
}
