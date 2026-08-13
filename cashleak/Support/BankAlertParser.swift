import Foundation

/// Extracts an amount and a merchant from a bank alert.
///
/// **Half of L2.** The other half — whether Shortcuts actually hands us the
/// message body — can only be answered on a physical phone. This half is ours
/// and is testable anywhere.
///
/// Building it now is deliberate: if the on-device test comes back positive,
/// the feature is a wiring job rather than a week's work. If it comes back
/// negative, this file is dead code and gets deleted. That's an acceptable bet
/// on a few hundred lines.
///
/// Every parse lands in the Sort queue **unconfirmed**, which is what makes a
/// wrong extraction survivable — the user sees a nonsense merchant and swipes it
/// away rather than finding it inside a total three weeks later.
enum BankAlertParser {

    struct Result: Equatable {
        let amount: Double
        let merchant: String?
        /// How much of the message we understood. Low confidence still enters
        /// the queue — it just isn't worth guessing a merchant for.
        let confidence: Confidence

        enum Confidence: String, Equatable {
            /// Amount and merchant both found in expected positions.
            case high
            /// Amount found, merchant guessed or absent.
            case medium
            /// Amount found by fallback scan. Suspect.
            case low
        }
    }

    /// Alerts that must never become transactions.
    ///
    /// Banks send far more than purchase notifications, and a balance alert
    /// parsed as spending would be a large fictional number sitting in the
    /// month's totals.
    static let rejectionPhrases = [
        "balance", "available funds", "e-transfer received", "deposit",
        "payment received", "refund", "reversed", "declined", "insufficient",
        "statement is ready", "password", "verification code", "one-time",
        "fraud alert", "suspicious", "card was locked",
    ]

    /// Words that appear next to a purchase, used to raise confidence.
    private static let purchasePhrases = [
        "purchase", "was used", "transaction", "charged", "debit", "spent", "at",
    ]

    // MARK: Entry point

    static func parse(_ message: String) -> Result? {
        let lowered = message.lowercased()

        // Reject first. A false negative costs one manual entry; a false
        // positive corrupts the dataset.
        for phrase in rejectionPhrases where lowered.contains(phrase) {
            return nil
        }

        guard let amount = extractAmount(from: message), amount > 0 else { return nil }
        guard amount < 100_000 else { return nil }

        let merchant = extractMerchant(from: message)

        let looksLikePurchase = purchasePhrases.contains { lowered.contains($0) }
        let confidence: Result.Confidence
        if merchant != nil && looksLikePurchase {
            confidence = .high
        } else if looksLikePurchase {
            confidence = .medium
        } else {
            confidence = .low
        }

        return Result(amount: amount, merchant: merchant, confidence: confidence)
    }

    // MARK: Amount

    /// Finds the first currency-marked figure.
    ///
    /// Anchored on a currency symbol or code rather than scanning for any
    /// number — bank alerts are full of card digits, reference numbers and
    /// dates, any of which a naive scan would happily return as an amount.
    static func extractAmount(from message: String) -> Double? {
        let patterns = [
            #"(?:CAD|USD|EUR|GBP)\s*\$?\s*([0-9][0-9,]*\.?[0-9]{0,2})"#,
            #"[$€£]\s*([0-9][0-9,]*\.?[0-9]{0,2})"#,
            #"([0-9][0-9,]*\.[0-9]{2})\s*(?:CAD|USD|EUR|GBP|dollars)"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(message.startIndex..., in: message)
            guard let match = regex.firstMatch(in: message, range: range),
                  match.numberOfRanges > 1,
                  let captured = Swift.Range(match.range(at: 1), in: message)
            else { continue }

            let cleaned = message[captured].replacingOccurrences(of: ",", with: "")
            if let value = Double(cleaned) { return value }
        }
        return nil
    }

    // MARK: Merchant

    /// Pulls the merchant out of the phrasings Canadian banks actually use.
    ///
    /// These templates are guesses until real alerts are collected. When L2
    /// runs, replace them with what your bank genuinely sends — the same
    /// discipline as the Wallet merchant fixtures.
    static func extractMerchant(from message: String) -> String? {
        let patterns = [
            #"(?:at|to)\s+([A-Z0-9][A-Za-z0-9&'.\-* ]{2,40}?)(?:\s+on\s|\s+for\s|[.,;]|$)"#,
            #"merchant:?\s*([A-Za-z0-9&'.\-* ]{2,40}?)(?:[.,;]|$)"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(message.startIndex..., in: message)
            guard let match = regex.firstMatch(in: message, range: range),
                  match.numberOfRanges > 1,
                  let captured = Swift.Range(match.range(at: 1), in: message)
            else { continue }

            let candidate = message[captured]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;"))

            // A date or a bare number caught by "at" is not a merchant.
            guard candidate.count >= 2,
                  candidate.rangeOfCharacter(from: .letters) != nil,
                  !candidate.allSatisfy({ $0.isNumber || $0 == " " })
            else { continue }

            return candidate
        }
        return nil
    }

    // MARK: Bank presets

    /// Trigger phrases for the "Message contains" field, one per bank.
    ///
    /// Sender filtering may not accept the short codes banks text from, which
    /// would make these the only workable filter. Either way, a user shouldn't
    /// have to work out their own trigger phrase.
    struct Preset: Identifiable, Hashable {
        let bank: String
        let containsPhrase: String
        var id: String { bank }
    }

    static let presets: [Preset] = [
        Preset(bank: "RBC", containsPhrase: "RBC"),
        Preset(bank: "TD", containsPhrase: "TD"),
        Preset(bank: "Scotiabank", containsPhrase: "Scotiabank"),
        Preset(bank: "BMO", containsPhrase: "BMO"),
        Preset(bank: "CIBC", containsPhrase: "CIBC"),
        Preset(bank: "Tangerine", containsPhrase: "Tangerine"),
        Preset(bank: "Desjardins", containsPhrase: "Desjardins"),
        Preset(bank: "National Bank", containsPhrase: "National Bank"),
    ]

    #if DEBUG
    /// Alert shapes for exercising the parser without a phone.
    ///
    /// **Invented, not collected.** They're modelled on the phrasing patterns
    /// banks tend to use, which is not the same as being right. Replace them the
    /// moment real alerts are in hand.
    static let sampleAlerts: [(bank: String, text: String, shouldParse: Bool)] = [
        ("RBC", "RBC: A purchase of $34.20 was made at UBER EATS on your card ending 6411.", true),
        ("TD", "TD: Purchase of CAD 88.40 at LOBLAWS #1043 on card *2003.", true),
        ("Scotiabank", "Scotiabank alert: $6.75 charged at TIM HORTONS 4471.", true),
        ("BMO", "BMO: Your card was used for $120.00 at AMAZON.CA on Aug 12.", true),
        ("CIBC", "CIBC: Transaction of $15.99 to NETFLIX.COM completed.", true),
        ("Tangerine", "Tangerine: You spent $42.10 at PRESTO/METROLINX.", true),
        ("Balance", "RBC: Your available balance is $2,481.19.", false),
        ("Deposit", "TD: A deposit of $1,200.00 has been made to your account.", false),
        ("Declined", "CIBC: A purchase of $60.00 at SHELL was declined.", false),
        ("OTP", "Scotiabank: Your verification code is 884120. Do not share it.", false),
        ("Refund", "BMO: A refund of $25.00 from AMAZON has been processed.", false),
    ]
    #endif
}
