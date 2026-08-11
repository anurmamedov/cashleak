import Foundation
import SwiftData

/// A card the user has told us about, and whether they've wired its Shortcuts
/// automation.
///
/// **This is self-reported.** There is no API that lists a user's Wallet cards
/// or reports whether an automation exists — so the app can't detect any of it.
/// The user adds the card and marks it done.
///
/// That's a real weakness: someone can mark a card set up and be wrong. It's
/// still worth having, because the alternative is a settings screen that says
/// nothing about coverage, and coverage is the thing users will be confused
/// about. `lastCapturedAt` gives a factual counterweight to the claim — if a
/// card is marked active and hasn't captured anything in a month, the UI can
/// say so without accusing anyone.
@Model
final class CardAutomation {

    /// User's own label, e.g. "Visa ···6411".
    var label: String = ""

    /// Self-reported. Not verifiable.
    var isConfigured: Bool = false

    var createdAt: Date = Date.distantPast

    /// Set whenever a transaction arrives from Apple Pay while this is the only
    /// configured card. Best-effort — with several cards configured, arrivals
    /// can't be attributed.
    var lastCapturedAt: Date?

    init(label: String, isConfigured: Bool = false) {
        self.label = label
        self.isConfigured = isConfigured
        self.createdAt = .now
    }

    /// Configured, but nothing has arrived in a fortnight. Worth surfacing
    /// quietly — automations break when iOS updates, and silent failure is the
    /// worst outcome for a capture app.
    var looksStale: Bool {
        guard isConfigured else { return false }
        guard let last = lastCapturedAt else {
            return createdAt < Date.now.addingTimeInterval(-14 * 86_400)
        }
        return last < Date.now.addingTimeInterval(-14 * 86_400)
    }

    var statusText: String {
        if !isConfigured { return "Not set up" }
        if looksStale { return "No activity in 2 weeks" }
        return "Automation active"
    }
}
