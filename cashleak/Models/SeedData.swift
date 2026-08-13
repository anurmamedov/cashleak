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

    /// Fourteen days shaped like an honest L1 trial, with a behaviour change
    /// built into it.
    ///
    /// **This does not answer L1.** L1 asks whether labelling purchases changes
    /// what *you* buy, and no generated dataset can tell you that. What this
    /// does test is the instrument: if a real person's habits shifted mid-trial,
    /// would the app show it, or would the change hide inside the averages?
    ///
    /// Week one runs at roughly a third leaked — the ratio of someone logging
    /// honestly for the first time. Week two drops to under a fifth, with the
    /// delivery habit mostly gone. That's the shape of the mechanic working.
    /// If Overview and Analysis don't make that visible, the app is a diary
    /// rather than a tool.
    @MainActor
    static func generateTwoWeekTrial(seed: UInt64 = 7, in context: ModelContext) {
        seedCategoriesIfNeeded(in: context)

        let categories = (try? context.fetch(FetchDescriptor<Category>())) ?? []
        guard !categories.isEmpty else { return }

        var rng = SeededGenerator(seed: seed)
        let calendar = Calendar.current
        let today = Date.now

        // (merchant, category, low, high, leak chance week 1, leak chance week 2)
        let profiles: [(String, String, Double, Double, Double, Double)] = [
            ("Uber Eats",     "Delivery",      22, 48, 0.85, 0.80),
            ("DoorDash",      "Delivery",      24, 52, 0.85, 0.80),
            ("Tim Hortons",   "Coffee",         3, 11, 0.40, 0.25),
            ("Blue Bottle",   "Coffee",         5,  9, 0.35, 0.20),
            ("Terroni",       "Dining out",    38, 95, 0.30, 0.20),
            ("Loblaws",       "Groceries",     35,110, 0.03, 0.02),
            ("Presto",        "Transit",        7, 16, 0.02, 0.02),
            ("Amazon",        "Shopping",      18,120, 0.55, 0.35),
            ("Cineplex",      "Fun",           16, 42, 0.25, 0.20),
            ("Shoppers",      "Health",        11, 48, 0.12, 0.10),
        ]

        for dayOffset in stride(from: 13, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let isSecondWeek = dayOffset < 7
            let isWeekend = calendar.isDateInWeekend(day)

            // The behaviour change: fewer discretionary purchases in week two.
            let count = isSecondWeek
                ? Int.random(in: (isWeekend ? 2...4 : 1...3), using: &rng)
                : Int.random(in: (isWeekend ? 4...6 : 2...5), using: &rng)

            for _ in 0..<count {
                var profile = profiles.randomElement(using: &rng)!

                // Week two: the delivery habit is the thing that actually got
                // dropped. Re-roll most of those into groceries.
                if isSecondWeek, profile.1 == "Delivery",
                   Double.random(in: 0...1, using: &rng) < 0.7 {
                    profile = profiles.first { $0.0 == "Loblaws" }!
                }

                let amount = (Double.random(in: profile.2...profile.3, using: &rng) * 100).rounded() / 100
                let hour = Int.random(in: 7...21, using: &rng)
                let date = calendar.date(bySettingHour: hour, minute: Int.random(in: 0...59, using: &rng), second: 0, of: day) ?? day

                let leakChance = isSecondWeek ? profile.5 : profile.4
                let verdict: Verdict = Double.random(in: 0...1, using: &rng) < leakChance ? .leak : .worthIt

                let transaction = Transaction(
                    amount: amount,
                    date: date,
                    merchant: profile.0,
                    source: dayOffset == 0 ? .applePay : .manual,
                    verdict: dayOffset == 0 ? .unrated : verdict,
                    // Today's stay unsorted, so the queue has something in it —
                    // which is what the trial actually feels like each evening.
                    isConfirmed: dayOffset != 0,
                    category: categories.first { $0.name == profile.1 }
                )
                context.insert(transaction)
            }
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
