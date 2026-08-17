import Foundation

/// Plain CSV export.
///
/// The app promises no financial-data lock-in — your data remains exportable
/// from the phone. The export includes
/// superseded rows with a flag, because hiding them would make the export
/// disagree with the totals in the app.
enum CSVExport {

    static let header = "date,merchant,amount,currency,category,verdict,source,confirmed,superseded,note"

    static func makeCSV(from transactions: [Transaction]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate]

        let rows = transactions
            .sorted { $0.date < $1.date }
            .map { transaction in
                [
                    formatter.string(from: transaction.date),
                    escape(transaction.merchant),
                    String(format: "%.2f", transaction.amount),
                    transaction.currencyCode,
                    escape(transaction.category?.name ?? ""),
                    transaction.verdict.rawValue,
                    transaction.source.rawValue,
                    transaction.isConfirmed ? "true" : "false",
                    transaction.isSuperseded ? "true" : "false",
                    escape(transaction.note),
                ].joined(separator: ",")
            }

        return ([header] + rows).joined(separator: "\n")
    }

    /// Quotes any field containing a comma, quote, or newline, per RFC 4180.
    /// Merchant strings from real card feeds contain all three.
    static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Writes to a temporary file and returns its URL, for the share sheet.
    static func writeTemporaryFile(from transactions: [Transaction]) throws -> URL {
        let csv = makeCSV(from: transactions)
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cashleak-\(stamp).csv")
        try csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
