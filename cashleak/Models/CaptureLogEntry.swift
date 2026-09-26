import Foundation
import SwiftData

/// A verbatim record of what a capture source actually sent.
///
/// This exists for L3. The gate's real deliverable is ten or more merchant
/// strings exactly as the Wallet trigger delivers them, because the dedup
/// matcher and merchant normalizer are currently tuned against invented
/// fixtures. Writing those strings on paper while standing at a till is how
/// they get mistyped or skipped.
///
/// So the app records them itself. Tap-pay a few times, then read the log —
/// including how the normalizer handled each one, which is the part that
/// actually matters.
///
/// Separate from `Transaction` on purpose. This is diagnostic data about the
/// *pipeline*, not money. It never reaches a total, and clearing it destroys
/// nothing.
@Model
final class CaptureLogEntry {

    /// Exactly as received. Never trimmed, never normalized — the whole point
    /// is to see what arrives before anything touches it.
    var rawMerchant: String = ""

    var amount: Double = 0

    /// What `MerchantNormalizer` made of it. Recorded at capture time so a
    /// later change to the rules doesn't rewrite history.
    var normalizedAtCapture: String = ""

    /// When the app received it. Compared against the receipt time by hand,
    /// this gives the trigger's real latency — one of L3's questions.
    var receivedAt: Date = Date.distantPast

    var sourceRaw: String = TransactionSource.applePay.rawValue

    /// What the ingest funnel decided. A rejected entry is as interesting as an
    /// accepted one — it's how declines show up.
    var outcome: String = ""

    /// Everything else the trigger offered, verbatim.
    ///
    /// Temporary, and deliberately unstructured. We know the Wallet trigger
    /// publishes Amount and Merchant because those are the two we read. What
    /// else is in the payload — the card, a transaction type, a timestamp, a
    /// merchant category — is currently a matter of reasoning rather than
    /// observation, and reasoning about an undocumented Apple payload is how
    /// the last three L3 findings got missed.
    ///
    /// So the setup instructions ask the user to drop every remaining variable
    /// Shortcuts offers into one field, and this stores whatever comes back. One
    /// tap-pay then answers the question outright. Once the payload is known,
    /// the real fields get named parameters and this comes out again.
    var rawDetails: String = ""

    /// Something arrived beyond amount and merchant.
    var hasDetails: Bool {
        !rawDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var source: TransactionSource {
        get { TransactionSource(rawValue: sourceRaw) ?? .applePay }
        set { sourceRaw = newValue.rawValue }
    }

    /// The normalizer changed the string. Worth seeing at a glance — an
    /// unchanged string means the rules did nothing.
    var wasTransformed: Bool {
        normalizedAtCapture != rawMerchant.lowercased()
    }

    init(
        rawMerchant: String,
        amount: Double,
        source: TransactionSource,
        outcome: String,
        rawDetails: String = ""
    ) {
        self.rawMerchant = rawMerchant
        self.amount = amount
        self.normalizedAtCapture = MerchantNormalizer.normalize(rawMerchant)
        self.receivedAt = .now
        self.sourceRaw = source.rawValue
        self.outcome = outcome
        self.rawDetails = rawDetails
    }
}

/// Writes capture log entries and exports them in a form that can be pasted
/// straight into the test fixtures.
enum CaptureLog {

    /// Capped so a long-running install doesn't accumulate diagnostic data
    /// forever. Fifty is far more than L3 needs.
    static let limit = 50

    @MainActor
    static func record(
        rawMerchant: String?,
        amount: Double,
        source: TransactionSource,
        outcome: String,
        rawDetails: String? = nil,
        in context: ModelContext
    ) {
        let entry = CaptureLogEntry(
            rawMerchant: rawMerchant ?? "",
            amount: amount,
            source: source,
            outcome: outcome,
            rawDetails: rawDetails ?? ""
        )
        context.insert(entry)

        var descriptor = FetchDescriptor<CaptureLogEntry>(
            sortBy: [SortDescriptor(\.receivedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit + 20

        if let all = try? context.fetch(descriptor), all.count > limit {
            for stale in all.dropFirst(limit) { context.delete(stale) }
        }

        try? context.save()
    }

    /// Formats the log as Swift ready to paste into `TestSupport`.
    ///
    /// The `expected` side is left as the current normalizer output, which is a
    /// starting point rather than an answer — the point of L3 is to find where
    /// that output is wrong.
    static func fixtureExport(_ entries: [CaptureLogEntry]) -> String {
        let lines = entries
            .filter { !$0.rawMerchant.isEmpty }
            .map { entry in
                let raw = entry.rawMerchant.replacingOccurrences(of: "\"", with: "\\\"")
                return "        (\"\(raw)\", \"\(entry.normalizedAtCapture)\"),"
            }

        return """
        // Captured \(Date.now.formatted(date: .abbreviated, time: .shortened))
        // Check every `expected` value by hand before trusting it — these are
        // what the normalizer currently produces, not what it should produce.
        static let merchantFixtures: [(raw: String, expected: String)] = [
        \(lines.joined(separator: "\n"))
        ]
        """
    }

    /// Dumps the unstructured payload field for every entry that has one.
    ///
    /// Not fixture code — this is for reading. It is how we find out what the
    /// Wallet trigger actually publishes, which decides whether the card,
    /// transaction type or a merchant category are worth named parameters.
    static func payloadExport(_ entries: [CaptureLogEntry]) -> String {
        let blocks = entries.filter(\.hasDetails).map { entry in
            """
            --- \(entry.receivedAt.formatted(date: .abbreviated, time: .standard))
            merchant: \(entry.rawMerchant.isEmpty ? "(none)" : entry.rawMerchant)
            amount:   \(entry.amount)
            details:
            \(entry.rawDetails)
            """
        }

        guard !blocks.isEmpty else {
            return """
            No payload details recorded.

            The automation is passing only Amount and Merchant. Add the Details
            field — see Settings › Apple Pay, step 8 — and tap-pay once more.
            """
        }

        return """
        Wallet trigger payload, \(blocks.count) capture\(blocks.count == 1 ? "" : "s").
        Field names and formats are whatever Shortcuts sent; nothing here has
        been interpreted.

        \(blocks.joined(separator: "\n\n"))
        """
    }

    @MainActor
    static func clear(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<CaptureLogEntry>())) ?? []
        for entry in all { context.delete(entry) }
        try? context.save()
    }
}
