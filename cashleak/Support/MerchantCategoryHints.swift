import Foundation

/// Suggests a category from a merchant name.
///
/// This exists because of an L3 finding. Wallet does not hand over the
/// processor string — it resolves the merchant against Maps first and delivers
/// a clean name: `Tim Hortons`, `No Frills`, `Walmart Supercentre`, not
/// `TST* TIM HORTONS #4412 TORONTO ON`. Apple states this outright in the
/// transaction detail screen: *Wallet uses Maps to provide merchant name,
/// category, and location*.
///
/// A clean name is matchable. `SQ *BLUE BOTTLE #4412` is not worth pattern
/// matching against; `Blue Bottle` is. So the single largest piece of friction
/// in the Sort queue — picking a category for the same coffee shop for the
/// fortieth time — can be removed for the merchants people actually visit.
///
/// **This suggests a category and nothing else.** It never sets a verdict, and
/// there is no waste flag anywhere in this file. Whether a coffee was worth
/// buying is the entire product and is not a property of the shop — see D-002
/// and the verdict rule in CLAUDE.md. Filing something under Coffee says only
/// where the money went.
///
/// Precedence, weakest last:
/// 1. A category the user already chose for this merchant (`MerchantMemory`)
/// 2. This table
/// 3. Nothing — the user picks
///
/// The user's own history always wins. Recategorise `Tim Hortons` to Dining out
/// once and the table is out of the picture for that merchant forever.
enum MerchantCategoryHints {

    /// Normalized merchant fragment → default category name.
    ///
    /// Matched against `MerchantNormalizer.normalize` output, so everything here
    /// is lowercase and free of punctuation. Names are the Maps-resolved forms
    /// Wallet delivers; where a chain is known by a shorter name too, both are
    /// listed rather than relying on fuzzy matching.
    ///
    /// Canadian-first, because the app's defaults are. This is a convenience
    /// layer, not a directory — a merchant missing from it costs one tap, which
    /// is what every merchant costs today.
    private static let table: [(fragment: String, category: String)] = [

        // Groceries
        ("no frills", "Groceries"),
        ("loblaws", "Groceries"),
        ("sobeys", "Groceries"),
        ("metro", "Groceries"),
        ("food basics", "Groceries"),
        ("freshco", "Groceries"),
        ("farm boy", "Groceries"),
        ("longos", "Groceries"),
        ("zehrs", "Groceries"),
        ("save on foods", "Groceries"),
        ("superstore", "Groceries"),
        ("walmart", "Groceries"),
        ("costco", "Groceries"),
        ("whole foods", "Groceries"),
        ("t t supermarket", "Groceries"),

        // Coffee
        ("tim hortons", "Coffee"),
        ("starbucks", "Coffee"),
        ("second cup", "Coffee"),
        ("balzacs", "Coffee"),
        ("blue bottle", "Coffee"),
        ("aroma espresso", "Coffee"),
        ("coffee", "Coffee"),
        ("cafe", "Coffee"),

        // Dining out
        ("sushi", "Dining out"),
        ("restaurant", "Dining out"),
        ("pizzeria", "Dining out"),
        ("pizza", "Dining out"),
        ("mcdonalds", "Dining out"),
        ("subway", "Dining out"),
        ("wendys", "Dining out"),
        ("burger king", "Dining out"),
        ("popeyes", "Dining out"),
        ("swiss chalet", "Dining out"),
        ("harveys", "Dining out"),
        ("a w", "Dining out"),
        ("kfc", "Dining out"),
        ("chipotle", "Dining out"),
        ("shawarma", "Dining out"),
        ("kitchen", "Dining out"),
        ("grill", "Dining out"),
        ("bar", "Dining out"),

        // Delivery
        ("uber eats", "Delivery"),
        ("doordash", "Delivery"),
        ("skip the dishes", "Delivery"),
        ("skipthedishes", "Delivery"),
        ("instacart", "Delivery"),

        // Transit — "uber" after "uber eats" so the longer fragment wins
        ("presto", "Transit"),
        ("metrolinx", "Transit"),
        ("go transit", "Transit"),
        ("ttc", "Transit"),
        ("uber", "Transit"),
        ("lyft", "Transit"),
        ("parking", "Transit"),
        ("green p", "Transit"),

        // Fuel
        ("petro canada", "Fuel"),
        ("petrocanada", "Fuel"),
        ("esso", "Fuel"),
        ("shell", "Fuel"),
        ("husky", "Fuel"),
        ("ultramar", "Fuel"),
        ("pioneer", "Fuel"),

        // Subscriptions
        ("netflix", "Subscriptions"),
        ("spotify", "Subscriptions"),
        ("disney", "Subscriptions"),
        ("crave", "Subscriptions"),
        ("youtube premium", "Subscriptions"),
        ("icloud", "Subscriptions"),
        ("dropbox", "Subscriptions"),
        ("patreon", "Subscriptions"),

        // Health
        ("shoppers drug mart", "Health"),
        ("rexall", "Health"),
        ("pharmacy", "Health"),
        ("pharmaprix", "Health"),
        ("dental", "Health"),
        ("clinic", "Health"),

        // Shopping
        ("canadian tire", "Shopping"),
        ("home depot", "Shopping"),
        ("rona", "Shopping"),
        ("ikea", "Shopping"),
        ("winners", "Shopping"),
        ("marshalls", "Shopping"),
        ("hudsons bay", "Shopping"),
        ("indigo", "Shopping"),
        ("chapters", "Shopping"),
        ("dollarama", "Shopping"),
        ("sportchek", "Shopping"),
        ("amazon", "Shopping"),
        ("apple", "Shopping"),
        ("best buy", "Shopping"),

        // Phone
        ("rogers", "Phone"),
        ("bell", "Phone"),
        ("telus", "Phone"),
        ("freedom mobile", "Phone"),
        ("fido", "Phone"),
        ("koodo", "Phone"),

        // Fun
        ("cineplex", "Fun"),
        ("cinema", "Fun"),
        ("theatre", "Fun"),
        ("lcbo", "Fun"),
        ("beer store", "Fun"),
    ]

    /// The category name suggested for a merchant, or `nil` when nothing fits.
    ///
    /// Longest fragment wins, which is the whole reason the table can hold both
    /// `uber eats` and `uber`: a Delivery match beats a Transit one because it
    /// is more specific, regardless of the order entries appear above. Relying
    /// on array order for that would break the first time someone added a line
    /// in the wrong place.
    ///
    /// Matching is on **whole words only**. A bare substring test is tempting
    /// and wrong: `bar` would match Barber Shop, `apple` would match Pineapple
    /// Express, and a miscategorised transaction is worse than an uncategorised
    /// one because the user has no reason to look at it.
    static func categoryName(forMerchant merchant: String) -> String? {
        let normalized = MerchantNormalizer.normalize(merchant)
        guard !normalized.isEmpty else { return nil }

        // Possessives arrive split. The normalizer turns punctuation into
        // spaces, so `McDonald's` becomes `mcdonald s` and `Hudson's Bay`
        // becomes `hudson s bay` — neither matches a table written the way the
        // sign outside reads. Rejoining the orphaned `s` handles every
        // possessive chain with one rule, instead of a second spelling per row
        // that someone will forget to add.
        // Padded before rejoining, so a trailing possessive — `mcdonald s`, with
        // nothing after it — is caught as well as a medial one.
        let padded = " \(normalized) "
        let rejoined = padded.replacingOccurrences(of: " s ", with: "s ")
        let candidates = [padded, rejoined]

        return table
            .filter { entry in
                candidates.contains { $0.contains(" \(entry.fragment) ") }
            }
            .max { $0.fragment.count < $1.fragment.count }?
            .category
    }
}
