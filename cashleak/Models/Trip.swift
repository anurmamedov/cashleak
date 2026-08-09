import Foundation
import SwiftData

/// A planned or in-progress trip.
///
/// The forecast is personalised: the user's own daily discretionary spend times
/// a destination cost multiplier, rather than a generic per-diem.
@Model
final class Trip {

    var name: String = ""
    var destination: String = ""
    var startDate: Date = Date.distantPast
    var endDate: Date = Date.distantPast

    /// Flights, lodging, and anything else not billed per day.
    var fixedCosts: Double = 0

    /// Destination cost relative to home. Lisbon at 0.8 is 20% cheaper than
    /// Toronto. Sourced from the curated city index in Resources.
    var costMultiplier: Double = 1.0

    /// Snapshot of the user's daily discretionary spend when the forecast was
    /// made. Stored rather than recomputed so a past trip's estimate doesn't
    /// drift as later spending changes the average.
    var dailyDiscretionaryAtEstimate: Double = 0

    @Relationship(inverse: \Transaction.trip)
    var transactions: [Transaction]?

    // MARK: Derived

    var dayCount: Int {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        return max(days, 1)
    }

    /// `daily discretionary × destination multiplier × days + fixed costs`
    var estimatedBudget: Double {
        dailyDiscretionaryAtEstimate * costMultiplier * Double(dayCount) + fixedCosts
    }

    var isActive: Bool {
        let now = Date.now
        return now >= startDate && now <= endDate
    }

    var isUpcoming: Bool { Date.now < startDate }

    var daysRemaining: Int {
        guard isActive else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: .now, to: endDate).day ?? 0
        return max(days, 0)
    }

    var actualSpend: Double {
        (transactions ?? [])
            .filter(\.countsTowardTotals)
            .reduce(0) { $0 + $1.amount }
    }

    /// Spend per day so far. Compare against the daily allowance to show whether
    /// the trip is on pace.
    var burnRate: Double {
        let elapsed = Calendar.current.dateComponents([.day], from: startDate, to: min(.now, endDate)).day ?? 0
        return actualSpend / Double(max(elapsed, 1))
    }

    var dailyAllowance: Double {
        dailyDiscretionaryAtEstimate * costMultiplier
    }

    init(
        name: String,
        destination: String = "",
        startDate: Date,
        endDate: Date,
        fixedCosts: Double = 0,
        costMultiplier: Double = 1.0,
        dailyDiscretionaryAtEstimate: Double = 0
    ) {
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.fixedCosts = fixedCosts
        self.costMultiplier = costMultiplier
        self.dailyDiscretionaryAtEstimate = dailyDiscretionaryAtEstimate
    }
}
