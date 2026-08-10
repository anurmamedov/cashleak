import Foundation
import SwiftData
import XCTest
@testable import cashleak

/// Shared helpers for the test suite.
enum TestSupport {

    /// A real SwiftData stack held entirely in memory.
    ///
    /// `cloudKitDatabase: .none` matters — the app's container uses
    /// `.automatic`, and a test run that tries to reach CloudKit is slow,
    /// flaky, and dependent on whoever is signed in on the machine.
    @MainActor
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Transaction.self,
            Category.self,
            Trip.self,
            RecurringRule.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Calendar pinned to Toronto so DST tests are deterministic wherever they
    /// run — including CI in UTC.
    static var torontoCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Toronto")!
        return calendar
    }

    static func date(
        _ year: Int, _ month: Int, _ day: Int,
        hour: Int = 12, minute: Int = 0,
        calendar: Calendar = TestSupport.torontoCalendar
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    /// A confirmed transaction, which is what aggregates actually count.
    static func confirmed(
        _ amount: Double,
        verdict: Verdict,
        date: Date = .now,
        merchant: String = "Test",
        category: Category? = nil
    ) -> Transaction {
        Transaction(
            amount: amount,
            date: date,
            merchant: merchant,
            source: .manual,
            verdict: verdict,
            isConfirmed: true,
            category: category
        )
    }

    /// Real merchant strings as capture sources tend to deliver them.
    ///
    /// These are placeholders until L3 runs. **Replace them with strings your
    /// own card actually produces** — the dedup matcher is only as good as the
    /// fixtures it was tuned against, and every bank formats differently.
    static let merchantFixtures: [(raw: String, expected: String)] = [
        ("SQ *BLUE BOTTLE COFFEE",   "blue bottle coffee"),
        ("BLUE BOTTLE #4412",        "blue bottle"),
        ("BLUE BOTTLE TORONTO ON",   "blue bottle toronto"),
        ("TST* TERRONI",             "terroni"),
        ("UBER   EATS",              "uber eats"),
        ("LOBLAWS #1043 TORONTO ON", "loblaws toronto"),
        ("SHELL C12345",             "shell c12345"),
        ("Amazon.ca*MT4XY9",         "amazon ca mt4xy9"),
        ("NETFLIX.COM",              "netflix com"),
        ("PRESTO/METROLINX",         "presto metrolinx"),
    ]
}
