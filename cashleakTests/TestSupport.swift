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
        // Reuse the app's schema rather than restating it. The hand-written
        // copy had already drifted — it still listed `Trip`, which no longer
        // exists, and was missing `CardAutomation`, `UserProfile` and
        // `CaptureLogEntry`, so any test inserting one of those would fail at
        // runtime for a reason that has nothing to do with what it's testing.
        let schema = AppModelContainer.schema
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
        category: cashleak.Category? = nil
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

    /// Merchant strings as **Wallet** delivers them.
    ///
    /// Observed during L3, and not what this file used to assume. Wallet does
    /// not pass the processor string through — it resolves the merchant against
    /// Maps and hands over a clean display name. Apple says so in the
    /// transaction detail screen: *Wallet uses Maps to provide merchant name,
    /// category, and location.*
    ///
    /// So the normalizer's job on this path is almost nothing, and these
    /// fixtures pin that down: a clean name must survive intact. The risk is no
    /// longer under-stripping, it's a rule mangling a name that was already
    /// correct.
    ///
    /// Still worth capturing your own — chains vary by region and these are one
    /// Toronto card's worth.
    static let walletMerchantFixtures: [(raw: String, expected: String)] = [
        ("Tim Hortons",          "tim hortons"),
        ("No Frills",            "no frills"),
        ("Sobeys",               "sobeys"),
        ("Canadian Tire",        "canadian tire"),
        ("Walmart Supercentre",  "walmart supercentre"),
        ("Hatsu Sushi",          "hatsu sushi"),
        ("Apple",                "apple"),
        ("Solmaz",               "solmaz"),
    ]

    /// Processor strings, as the noisier paths deliver them.
    ///
    /// These are **not** dead. Receipt scanning reads whatever is printed, bank
    /// alerts quote the processor descriptor, and manual entry is whatever the
    /// user types. The prefix and store-number stripping exists for these, and
    /// removing it because Wallet doesn't need it would break the other three
    /// capture paths.
    ///
    /// Unlike the Wallet set, these remain guesses until L2 supplies real bank
    /// alert text.
    static let processorMerchantFixtures: [(raw: String, expected: String)] = [
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

    /// Both sets, for tests that don't care where a string came from.
    static let merchantFixtures: [(raw: String, expected: String)] =
        walletMerchantFixtures + processorMerchantFixtures
}
