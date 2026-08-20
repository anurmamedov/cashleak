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

    static var description = IntentDescription(
        "Records an Apple Pay transaction in CashLeak. It arrives unconfirmed, ready to sort.",
        categoryName: "Capture"
    )

    /// Never bring the UI forward — this runs mid-checkout.
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Merchant")
    var merchant: String?

    /// Optional so the automation can pass the transaction's own timestamp when
    /// Shortcuts provides one. Defaults to now.
    @Parameter(title: "Date")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = AppModelContainer.shared.mainContext

        let result = TransactionIngest.ingest(
            amount: amount,
            merchant: merchant,
            date: date ?? .now,
            source: .applePay,
            into: context
        )

        // Record what actually arrived, before anything interpreted it.
        // This is L3's data collection — see `CaptureLogEntry`.
        CaptureLog.record(
            rawMerchant: merchant,
            amount: amount,
            source: .applePay,
            outcome: {
                switch result {
                case .inserted: "inserted"
                case .duplicate: "duplicate"
                case .rejected(let reason): "rejected: \(reason.rawValue)"
                }
            }(),
            in: context
        )
        await DailyReminderScheduler.refresh(in: context)
        WidgetSnapshotUpdater.refresh(in: context)

        // Dialog text is deliberately terse. It can surface as a banner while
        // the user is still at the till, so it states the outcome and stops.
        switch result {
        case .inserted:
            return .result(dialog: "Logged \(amount.currencyExact)")
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
