import Foundation

/// Where a transaction came from.
///
/// Stored as `String` raw values rather than `Int` so that reordering or
/// inserting cases can never silently remap existing records.
enum TransactionSource: String, Codable, CaseIterable, Sendable {
    case applePay
    case bankAlert
    case scan
    case recurring
    case manual

    /// Short badge text shown on Sort queue rows.
    var badge: String {
        switch self {
        case .applePay: "Pay"
        case .bankAlert: "Alert"
        case .scan: "Scan"
        case .recurring: "Auto"
        case .manual: "Manual"
        }
    }
}

/// The user's judgement on a purchase. Never inferred, never derived from
/// category — see DECISIONS.md D-002.
enum Verdict: String, Codable, CaseIterable, Sendable {
    case worthIt
    case leak
    case unrated
}

/// Whether a category covers something needed or something chosen.
///
/// This is a display and grouping aid only. It must never influence `Verdict`.
enum CategoryKind: String, Codable, CaseIterable, Sendable {
    case need
    case want
}

/// How often a recurring rule posts.
enum Cadence: String, Codable, CaseIterable, Sendable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case yearly

    var displayName: String {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .yearly: "Yearly"
        }
    }

    /// The component and count to advance a date by one period.
    var step: (component: Calendar.Component, value: Int) {
        switch self {
        case .weekly: (.day, 7)
        case .biweekly: (.day, 14)
        case .monthly: (.month, 1)
        case .quarterly: (.month, 3)
        case .yearly: (.year, 1)
        }
    }
}
