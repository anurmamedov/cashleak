import Foundation
import SwiftData

/// First-launch categories and the debug dataset generator.
enum SeedData {

    // MARK: Default categories

    /// Fourteen categories covering ordinary Canadian spending.
    ///
    /// `kind` marks needs and wants for grouping only. It must never influence
    /// a verdict — groceries can be a leak, and a want can be entirely worth it.
    static let defaultCategories: [(String, String, String, CategoryKind)] = [
        ("Groceries",     "cart",                    "639922", .need),
        ("Rent",          "house",                   "5F5E5A", .need),
        ("Utilities",     "bolt",                    "5F5E5A", .need),
        ("Transit",       "tram",                    "378ADD", .need),
        ("Fuel",          "fuelpump",                "378ADD", .need),
        ("Phone",         "antenna.radiowaves.left.and.right", "5F5E5A", .need),
        ("Insurance",     "shield",                  "5F5E5A", .need),
        ("Health",        "cross.case",              "1D9E75", .need),
        ("Dining out",    "fork.knife",              "D85A30", .want),
        ("Delivery",      "bag",                     "D85A30", .want),
        ("Coffee",        "cup.and.saucer",          "BA7517", .want),
        ("Subscriptions", "repeat",                  "7F77DD", .want),
        ("Shopping",      "tshirt",                  "D4537E", .want),
        ("Fun",           "ticket",                  "7F77DD", .want),
    ]

    /// Inserts the default categories exactly once.
    ///
    /// Guarded by a count check rather than a stored flag so that a user who
    /// deletes every category doesn't get them silently reinstated on the next
    /// launch — that would be the app overruling them.
    @MainActor
    static func seedCategoriesIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<Category>()
        let existing = (try? context.fetchCount(descriptor)) ?? 0
        guard existing == 0 else { return }

        for (index, spec) in defaultCategories.enumerated() {
            let category = Category(
                name: spec.0,
                icon: spec.1,
                colorHex: spec.2,
                kind: spec.3,
                sortIndex: index
            )
            context.insert(category)
        }
        try? context.save()
    }

    // MARK: Debug dataset

    #if DEBUG

    /// Merchants paired with the category they usually belong to, and how
    /// likely a purchase there is to be judged a leak.
    private static let merchantProfiles: [(merchant: String, category: String, low: Double, high: Double, leakBias: Double)] = [
        ("Loblaws",        "Groceries",     40, 120, 0.05),
        ("Metro",          "Groceries",     25, 90,  0.05),
        ("Presto",         "Transit",       10, 40,  0.02),
        ("Shell",          "Fuel",          45, 80,  0.05),
        ("Uber Eats",      "Delivery",      18, 55,  0.75),
        ("DoorDash",       "Delivery",      20, 60,  0.75),
        ("Blue Bottle",    "Coffee",         4, 9,   0.45),
        ("Tim Hortons",    "Coffee",         3, 12,  0.35),
        ("Terroni",        "Dining out",    35, 110, 0.35),
        ("Pizzeria Libre", "Dining out",    22, 70,  0.40),
        ("Spotify",        "Subscriptions", 11, 12,  0.30),
        ("Netflix",        "Subscriptions", 17, 23,  0.55),
        ("Amazon",         "Shopping",      15, 140, 0.50),
        ("Uniqlo",         "Shopping",      30, 120, 0.35),
        ("Cineplex",       "Fun",           15, 45,  0.30),
        ("Shoppers",       "Health",        12, 60,  0.15),
    ]

    /// Generates `months` of plausible history.
    ///
    /// Deterministic for a given seed so charts, empty states, and tests are
    /// reproducible. Change the seed to see a different but equally plausible
    /// month; keep it fixed when comparing UI changes.
    @MainActor
    static func generate(
        months: Int = 4,
        seed: UInt64 = 42,
        in context: ModelContext
    ) {
        seedCategoriesIfNeeded(in: context)

        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        guard !categories.isEmpty else { return }

        var rng = SeededGenerator(seed: seed)
        let calendar = Calendar.current
        let today = Date.now

        guard let start = calendar.date(byAdding: .month, value: -months, to: today) else { return }

        var cursor = start
        while cursor < today {
            // Two to five purchases a day, weekends busier.
            let isWeekend = calendar.isDateInWeekend(cursor)
            let count = Int.random(in: (isWeekend ? 3...6 : 1...4), using: &rng)

            for _ in 0..<count {
                let profile = merchantProfiles.randomElement(using: &rng)!
                let amount = (Double.random(in: profile.low...profile.high, using: &rng) * 100).rounded() / 100

                let hour = Int.random(in: 7...22, using: &rng)
                let minute = Int.random(in: 0...59, using: &rng)
                let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: cursor) ?? cursor

                let category = categories.first { $0.name == profile.category }

                // Recent items stay unconfirmed so the Sort queue has content.
                let daysAgo = calendar.dateComponents([.day], from: date, to: today).day ?? 0
                let isConfirmed = daysAgo > 2

                let verdict: Verdict
                if isConfirmed {
                    verdict = Double.random(in: 0...1, using: &rng) < profile.leakBias ? .leak : .worthIt
                } else {
                    verdict = .unrated
                }

                let source: TransactionSource = {
                    let roll = Double.random(in: 0...1, using: &rng)
                    if profile.category == "Subscriptions" { return .recurring }
                    if roll < 0.55 { return .applePay }
                    if roll < 0.75 { return .manual }
                    if roll < 0.90 { return .scan }
                    return .bankAlert
                }()

                let transaction = Transaction(
                    amount: amount,
                    date: date,
                    merchant: profile.merchant,
                    source: source,
                    verdict: verdict,
                    isConfirmed: isConfirmed,
                    category: category
                )
                context.insert(transaction)
            }

            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? today
        }

        try? context.save()
    }

    /// Removes every transaction, leaving categories in place.
    @MainActor
    static func clearTransactions(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        for t in all { context.delete(t) }
        try? context.save()
    }

    #endif
}

#if DEBUG
/// Small linear congruential generator so seeded runs are reproducible.
/// `SystemRandomNumberGenerator` can't be seeded, and reproducibility is the
/// entire point of the debug dataset.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x4d595df4d0f33173 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}
#endif
