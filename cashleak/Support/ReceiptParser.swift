import Foundation
import CoreGraphics

/// One line of text read off a receipt, where it sat on the page.
///
/// `box` is in Vision's normalised space: 0…1 on both axes, origin at the
/// **bottom-left**, so a larger `midY` is higher up the receipt.
nonisolated struct ReceiptLine: Equatable, Sendable {
    let text: String
    let box: CGRect

    init(_ text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}

/// What a receipt says, as far as it could be read.
///
/// Three fields only — merchant, total, date (D-009). Each carries a
/// confidence so the Add sheet can mark the ones worth a second look rather
/// than guessing silently.
nonisolated struct ReceiptReading: Equatable, Sendable {

    enum Confidence: Equatable, Sendable {
        /// Found where it was expected, in the form expected.
        case sure
        /// A best guess. Shown with an orange dot.
        case check
    }

    struct Field<Value: Equatable & Sendable>: Equatable, Sendable {
        let value: Value
        let confidence: Confidence
    }

    var merchant: Field<String>?
    var total: Field<Double>?
    var date: Field<Date>?
    /// A starter category name suggested by words on the receipt — TIP means
    /// a restaurant, LITRES means fuel. Used only when the merchant itself
    /// gives no category.
    var categoryHint: String?

    var isEmpty: Bool { merchant == nil && total == nil && date == nil }
}

/// Turns recognised text into a `ReceiptReading`.
///
/// Pure and position-aware, so it's tested against line fixtures rather than
/// images. Vision does the reading; this decides what the words mean.
///
/// **Total** — the amount on a TOTAL / AMOUNT DUE / BALANCE DUE row, never a
/// SUBTOTAL, TAX or SAVINGS row. With a typed tip there are two totals; the
/// larger is the one paid. No keyword at all → the largest amount in the lower
/// two-thirds, marked *check*.
///
/// **Merchant** — the tallest text near the top, skipping addresses, phone
/// numbers and greetings.
///
/// **Date** — numeric or month-name forms. A day-month order that can't be
/// told apart (03/04/26) is marked *check*. Future dates and anything over two
/// years old are discarded as misreads.
nonisolated enum ReceiptParser {

    static let implausibleAmount: Double = 100_000

    static func parse(
        _ lines: [ReceiptLine],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ReceiptReading {
        let rows = rows(from: lines)
        guard !rows.isEmpty else { return ReceiptReading() }

        return ReceiptReading(
            merchant: merchant(in: rows),
            total: total(in: rows),
            date: date(in: rows, now: now, calendar: calendar),
            categoryHint: categoryHint(in: rows)
        )
    }

    // MARK: Rows

    /// A visual row: everything at the same height, left to right.
    ///
    /// Vision often returns `TOTAL` and `48.27` as two observations at
    /// opposite edges of the paper. Joining them is what makes "the amount on
    /// the TOTAL row" a meaningful question.
    struct Row: Equatable {
        let text: String
        let midY: Double
        let height: Double
    }

    static func rows(from lines: [ReceiptLine]) -> [Row] {
        let usable = lines
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.box.midY > $1.box.midY }

        var groups: [[ReceiptLine]] = []
        for line in usable {
            if let last = groups.last?.last,
               abs(last.box.midY - line.box.midY) < min(last.box.height, line.box.height) * 0.6 {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }

        return groups.map { group in
            let ordered = group.sorted { $0.box.minX < $1.box.minX }
            return Row(
                text: ordered.map(\.text).joined(separator: "  "),
                midY: group.map { Double($0.box.midY) }.reduce(0, +) / Double(group.count),
                height: group.map { Double($0.box.height) }.max() ?? 0
            )
        }
    }

    // MARK: Amounts

    private static let amountPattern = try! NSRegularExpression(
        pattern: #"(?<![\d.,/\-])\$?\s?(\d{1,3}(?:,\d{3})+|\d+)[.,](\d{2})(?![\d%/]|[.,]\d)"#
    )

    /// Every money-shaped figure in a string, left to right.
    static func amounts(in text: String) -> [Double] {
        let range = NSRange(text.startIndex..., in: text)
        return amountPattern.matches(in: text, range: range).compactMap { match in
            guard
                let whole = Range(match.range(at: 1), in: text),
                let cents = Range(match.range(at: 2), in: text)
            else { return nil }
            let digits = text[whole].replacingOccurrences(of: ",", with: "")
            guard let value = Double("\(digits).\(text[cents])"),
                  value > 0, value < implausibleAmount
            else { return nil }
            return value
        }
    }

    // MARK: Total

    private static let totalWords = ["GRAND TOTAL", "TOTAL", "AMOUNT DUE", "BALANCE DUE", "MONTANT DU", "MONTANT DÛ", "TOTAL DUE"]
    private static let notTotalWords = [
        "SUBTOTAL", "SUB TOTAL", "SUB-TOTAL", "SOUS-TOTAL", "SOUS TOTAL",
        "TAX", "TPS", "TVQ", "HST", "GST", "PST",
        "SAVING", "SAVED", "DISCOUNT", "RABAIS", "ITEMS", "ARTICLES",
        "POINTS", "CHANGE", "MONNAIE", "TIP", "POURBOIRE",
    ]
    private static let paymentWords = ["VISA", "MASTERCARD", "MASTER CARD", "AMEX", "DEBIT", "DÉBIT", "INTERAC", "CREDIT", "APPROVED", "APPROUV", "PAID", "PAYÉ"]

    static func total(in rows: [Row]) -> ReceiptReading.Field<Double>? {
        var candidates: [Double] = []

        for (index, row) in rows.enumerated() {
            let upper = row.text.uppercased()
            guard totalWords.contains(where: upper.contains) else { continue }
            let isGrand = upper.contains("GRAND TOTAL")
            // "TOTAL (TAX INCL.)" is still the total.
            let isInclusive = upper.contains("INCL")
            if !isGrand && !isInclusive && notTotalWords.contains(where: upper.contains) { continue }

            if let amount = amounts(in: row.text).last {
                candidates.append(amount)
            } else if index + 1 < rows.count,
                      rows[index + 1].midY > row.midY - row.height * 2.5,
                      let below = amounts(in: rows[index + 1].text).last {
                // Some receipts print the figure on the line under TOTAL.
                candidates.append(below)
            }
        }

        if let paid = candidates.max() {
            let distinct = Set(candidates)
            let onPaymentRow = rows.contains { row in
                let upper = row.text.uppercased()
                return paymentWords.contains(where: upper.contains) && amounts(in: row.text).contains(paid)
            }
            let sure = distinct.count == 1 || onPaymentRow
            return .init(value: paid, confidence: sure ? .sure : .check)
        }

        // No TOTAL row read. The largest figure in the lower two-thirds is
        // usually right, and visibly a guess.
        let lower = rows.suffix(max(1, rows.count * 2 / 3))
        let largest = lower.flatMap { amounts(in: $0.text) }.max()
        return largest.map { .init(value: $0, confidence: .check) }
    }

    // MARK: Merchant

    private static let notMerchantWords = [
        "WELCOME", "BIENVENUE", "RECEIPT", "REÇU", "RECU", "INVOICE", "FACTURE",
        "TEL", "PHONE", "WWW", "HTTP", ".COM", ".CA", "STORE #", "STORE:",
        "GST", "HST", "TPS", "TVQ", "REG #", "ORDER", "TABLE", "SERVER", "CASHIER",
        "CAISS", "TRANS", "THANK", "MERCI", "DATE", "TIME",
    ]

    static func merchant(in rows: [Row]) -> ReceiptReading.Field<String>? {
        let candidates = rows.prefix(6).filter { row in
            let upper = row.text.uppercased()
            // Counted after store numbers are stripped: LOBLAWS #1029 is a name.
            let cleaned = cleanMerchant(row.text)
            let letters = cleaned.filter(\.isLetter).count
            let digits = cleaned.filter(\.isNumber).count
            let startsWithNumber = row.text.trimmingCharacters(in: .whitespaces).first?.isNumber ?? false
            return letters >= 3
                && !startsWithNumber
                && digits <= letters / 2
                && !notMerchantWords.contains(where: upper.contains)
                && amounts(in: row.text).isEmpty
        }
        guard let best = candidates.prefix(4).max(by: { $0.height < $1.height }) else { return nil }

        let name = cleanMerchant(best.text)
        guard name.filter(\.isLetter).count >= 3 else { return nil }

        let others = candidates.prefix(4).filter { $0 != best }.map(\.height)
        let standsOut = others.allSatisfy { best.height >= $0 * 1.3 }
        return .init(value: name, confidence: standsOut ? .sure : .check)
    }

    /// `LOBLAWS #1029` → `Loblaws`. Store numbers and trailing codes go; an
    /// all-caps name gets ordinary capitals so it matches what Wallet sends.
    static func cleanMerchant(_ raw: String) -> String {
        var name = raw
            .replacingOccurrences(of: #"#\s?\d+.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+\d{2,}\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        if name == name.uppercased() {
            name = name.lowercased().capitalized
        }
        return name
    }

    // MARK: Date

    private static let months: [(String, Int)] = [
        ("JAN", 1), ("FEB", 2), ("FÉV", 2), ("FEV", 2), ("MAR", 3), ("APR", 4), ("AVR", 4),
        ("MAY", 5), ("MAI", 5), ("JUN", 6), ("JUIN", 6), ("JUL", 7), ("JUIL", 7),
        ("AUG", 8), ("AOÛ", 8), ("AOU", 8), ("SEP", 9), ("OCT", 10), ("NOV", 11),
        ("DEC", 12), ("DÉC", 12),
    ]

    private static let isoPattern = try! NSRegularExpression(
        pattern: #"\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b"#
    )
    private static let numericPattern = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})\b"#
    )
    private static let dayMonthNamePattern = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})[\s\-]*([A-ZÉÛ]{3,})\.?[\s,\-]*(\d{4}|\d{2})\b"#
    )
    private static let monthNameDayPattern = try! NSRegularExpression(
        pattern: #"\b([A-ZÉÛ]{3,})\.?\s+(\d{1,2}),?\s+(\d{4}|\d{2})\b"#
    )
    private static let timePattern = try! NSRegularExpression(
        pattern: #"\b([01]?\d|2[0-3]):([0-5]\d)\b"#
    )

    static func date(
        in rows: [Row],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> ReceiptReading.Field<Date>? {
        for row in rows {
            let text = row.text.uppercased()
            guard let (parts, sure) = dateParts(in: text) else { continue }

            var components = DateComponents(year: parts.year, month: parts.month, day: parts.day)
            if let time = firstMatch(timePattern, in: text) {
                components.hour = Int(time[0])
                components.minute = Int(time[1])
            } else {
                components.hour = 12
            }

            guard
                let date = calendar.date(from: components),
                calendar.component(.day, from: date) == parts.day,
                date <= now.addingTimeInterval(86_400),
                let earliest = calendar.date(byAdding: .year, value: -2, to: now),
                date >= earliest
            else { continue }

            // A purchase found in a pocket months later is real, but old
            // enough that a misread is the likelier story.
            let old = now.timeIntervalSince(date) > 60 * 86_400
            return .init(value: min(date, now), confidence: sure && !old ? .sure : .check)
        }
        return nil
    }

    private static func dateParts(in text: String) -> ((year: Int, month: Int, day: Int), Bool)? {
        if let m = firstMatch(isoPattern, in: text),
           let y = Int(m[0]), let mo = Int(m[1]), let d = Int(m[2]), valid(mo, d) {
            return ((y, mo, d), true)
        }
        if let m = firstMatch(numericPattern, in: text),
           let a = Int(m[0]), let b = Int(m[1]), let y = Int(m[2]) {
            let year = y < 100 ? 2000 + y : y
            if a > 12, valid(b, a) { return ((year, b, a), true) }
            if b > 12, valid(a, b) { return ((year, a, b), true) }
            // 03/04/26: month first is the common North American receipt
            // order, but it's a guess unless both readings agree.
            if valid(a, b) { return ((year, a, b), a == b) }
        }
        if let m = firstMatch(dayMonthNamePattern, in: text),
           let d = Int(m[0]), let mo = month(m[1]), let y = Int(m[2]), valid(mo, d) {
            return ((y < 100 ? 2000 + y : y, mo, d), true)
        }
        if let m = firstMatch(monthNameDayPattern, in: text),
           let mo = month(m[0]), let d = Int(m[1]), let y = Int(m[2]), valid(mo, d) {
            return ((y < 100 ? 2000 + y : y, mo, d), true)
        }
        return nil
    }

    private static func valid(_ month: Int, _ day: Int) -> Bool {
        (1...12).contains(month) && (1...31).contains(day)
    }

    private static func month(_ word: String) -> Int? {
        months.first { word.hasPrefix($0.0) }?.1
    }

    private static func firstMatch(_ pattern: NSRegularExpression, in text: String) -> [String]? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }

    // MARK: Category hint

    /// Receipt words that say what kind of place it was, strongest first.
    /// Matched as whole words so `TIPS` in a product name doesn't count.
    private static let categoryWords: [(String, [String])] = [
        ("Fuel", ["LITRE", "LITRES", "LITERS", "PUMP", "UNLEADED", "DIESEL", "FUEL", "ESSENCE"]),
        ("Dining out", ["TIP", "GRATUITY", "SERVER", "TABLE", "GUESTS", "POURBOIRE", "SERVEUR"]),
        ("Coffee", ["LATTE", "ESPRESSO", "AMERICANO", "CAPPUCCINO", "COFFEE", "CAFÉ"]),
        ("Health", ["PHARMACY", "PHARMACIE", "RX", "PRESCRIPTION"]),
        ("Groceries", ["PRODUCE", "GROCERY", "EPICERIE", "ÉPICERIE", "KG", "LB"]),
    ]

    static func categoryHint(in rows: [Row]) -> String? {
        let words = Set(
            rows.flatMap {
                $0.text.uppercased()
                    .components(separatedBy: CharacterSet.letters.inverted)
                    .filter { !$0.isEmpty }
            }
        )
        return categoryWords.first { $0.1.contains(where: words.contains) }?.0
    }
}
