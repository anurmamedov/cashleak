import Foundation

/// Reduces a raw merchant string to a comparable form.
///
/// Real capture sources are noisy. The same coffee shop arrives as
/// `SQ *BLUE BOTTLE COFFEE`, `BLUE BOTTLE #4412`, and `BLUE BOTTLE TORONTO ON`.
/// Dedup compares normalized forms, so this is where most of the matcher's
/// accuracy actually lives.
///
/// Fixtures for the test suite come from L3 — capture the real strings your own
/// card produces before relying on these rules.
enum MerchantNormalizer {

    /// Payment processor prefixes that appear ahead of the real merchant.
    private static let processorPrefixes = [
        "sq *", "sq*", "tst*", "tst *", "sp *", "sp*",
        "pp*", "pp *", "paypal *", "paypal*",
        "amzn mktp", "amazon mktpl",
    ]

    /// Trailing noise: province and state codes, and common suffixes.
    private static let trailingTokens: Set<String> = [
        "on", "qc", "bc", "ab", "mb", "sk", "ns", "nb", "nl", "pe", "yt", "nt", "nu",
        "ca", "can", "canada", "usa", "us",
        "inc", "ltd", "llc", "corp", "co",
    ]

    static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()

        for prefix in processorPrefixes where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
            break
        }

        // Strip anything that isn't a letter, digit, or space.
        s = s.map { $0.isLetter || $0.isNumber || $0.isWhitespace ? $0 : " " }
             .reduce(into: "") { $0.append($1) }

        // Drop store numbers and other bare digit runs.
        var tokens = s.split(separator: " ").map(String.init)
        tokens.removeAll { $0.allSatisfy(\.isNumber) }

        // Drop trailing location and entity suffixes, from the end only —
        // "co" mid-name is meaningful, "co" at the end is usually noise.
        while let last = tokens.last, trailingTokens.contains(last) {
            tokens.removeLast()
        }

        return tokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Whether two normalized merchants are close enough to be the same place.
    ///
    /// Exact match, safe phrase containment, or a Levenshtein distance within
    /// a length-scaled threshold. Containment is limited to multi-word names:
    /// `blue bottle` and `blue bottle coffee` are variants, while `uber` and
    /// `uber eats` are genuinely different merchants. Edit distance catches
    /// typos and truncation.
    static func isFuzzyMatch(_ a: String, _ b: String) -> Bool {
        if a.isEmpty || b.isEmpty { return false }
        if a == b { return true }

        let aWords = a.split(separator: " ")
        let bWords = b.split(separator: " ")
        let shorter = aWords.count <= bWords.count ? a : b
        let longer = aWords.count <= bWords.count ? b : a
        let shorterWordCount = min(aWords.count, bWords.count)
        if shorterWordCount >= 2 && " \(longer) ".contains(" \(shorter) ") {
            return true
        }

        let threshold = max(1, min(a.count, b.count) / 4)
        return levenshtein(a, b) <= threshold
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }

        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)

        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            previous = current
        }
        return previous[y.count]
    }
}
