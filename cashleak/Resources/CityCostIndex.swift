import Foundation

/// Daily discretionary cost relative to Toronto (1.00).
///
/// Hand-curated rather than fetched — a live cost-of-living API would mean a
/// backend, a per-user cost, and a subscription. This is one of the places the
/// no-server constraint costs something, and it's worth it.
///
/// The multiplier covers **discretionary daily spend**: food out, coffee,
/// transit, small purchases. Not rent, not flights. Those are fixed costs the
/// user enters directly.
///
/// Numbers are approximate by design. The value isn't precision — it's that
/// `your $34/day × 0.8` beats a generic "$80/day for food".
enum CityCostIndex {

    struct City: Identifiable, Hashable {
        let name: String
        let country: String
        let multiplier: Double
        var id: String { "\(name), \(country)" }

        var displayName: String { "\(name), \(country)" }
    }

    static let baseline = "Toronto"

    static let cities: [City] = [
        // Canada
        City(name: "Toronto", country: "Canada", multiplier: 1.00),
        City(name: "Vancouver", country: "Canada", multiplier: 1.05),
        City(name: "Montreal", country: "Canada", multiplier: 0.88),
        City(name: "Calgary", country: "Canada", multiplier: 0.92),
        City(name: "Ottawa", country: "Canada", multiplier: 0.90),
        City(name: "Halifax", country: "Canada", multiplier: 0.85),
        City(name: "Quebec City", country: "Canada", multiplier: 0.82),

        // United States
        City(name: "New York", country: "USA", multiplier: 1.45),
        City(name: "San Francisco", country: "USA", multiplier: 1.50),
        City(name: "Los Angeles", country: "USA", multiplier: 1.25),
        City(name: "Chicago", country: "USA", multiplier: 1.10),
        City(name: "Seattle", country: "USA", multiplier: 1.20),
        City(name: "Austin", country: "USA", multiplier: 1.05),
        City(name: "Miami", country: "USA", multiplier: 1.15),
        City(name: "Boston", country: "USA", multiplier: 1.30),
        City(name: "Denver", country: "USA", multiplier: 1.05),
        City(name: "New Orleans", country: "USA", multiplier: 0.95),

        // Western Europe
        City(name: "London", country: "UK", multiplier: 1.35),
        City(name: "Edinburgh", country: "UK", multiplier: 1.05),
        City(name: "Paris", country: "France", multiplier: 1.25),
        City(name: "Nice", country: "France", multiplier: 1.10),
        City(name: "Amsterdam", country: "Netherlands", multiplier: 1.20),
        City(name: "Berlin", country: "Germany", multiplier: 1.00),
        City(name: "Munich", country: "Germany", multiplier: 1.10),
        City(name: "Zurich", country: "Switzerland", multiplier: 1.65),
        City(name: "Vienna", country: "Austria", multiplier: 1.00),
        City(name: "Copenhagen", country: "Denmark", multiplier: 1.35),
        City(name: "Stockholm", country: "Sweden", multiplier: 1.15),
        City(name: "Oslo", country: "Norway", multiplier: 1.40),
        City(name: "Dublin", country: "Ireland", multiplier: 1.20),
        City(name: "Brussels", country: "Belgium", multiplier: 1.05),

        // Southern Europe
        City(name: "Lisbon", country: "Portugal", multiplier: 0.80),
        City(name: "Porto", country: "Portugal", multiplier: 0.72),
        City(name: "Madrid", country: "Spain", multiplier: 0.85),
        City(name: "Barcelona", country: "Spain", multiplier: 0.90),
        City(name: "Seville", country: "Spain", multiplier: 0.75),
        City(name: "Rome", country: "Italy", multiplier: 0.92),
        City(name: "Florence", country: "Italy", multiplier: 0.95),
        City(name: "Milan", country: "Italy", multiplier: 1.05),
        City(name: "Athens", country: "Greece", multiplier: 0.75),
        City(name: "Split", country: "Croatia", multiplier: 0.70),

        // Eastern Europe
        City(name: "Prague", country: "Czechia", multiplier: 0.68),
        City(name: "Budapest", country: "Hungary", multiplier: 0.60),
        City(name: "Warsaw", country: "Poland", multiplier: 0.62),
        City(name: "Krakow", country: "Poland", multiplier: 0.55),
        City(name: "Bucharest", country: "Romania", multiplier: 0.55),
        City(name: "Tbilisi", country: "Georgia", multiplier: 0.45),
        City(name: "Istanbul", country: "Turkey", multiplier: 0.48),

        // Asia
        City(name: "Tokyo", country: "Japan", multiplier: 0.95),
        City(name: "Kyoto", country: "Japan", multiplier: 0.88),
        City(name: "Seoul", country: "South Korea", multiplier: 0.90),
        City(name: "Singapore", country: "Singapore", multiplier: 1.15),
        City(name: "Hong Kong", country: "Hong Kong", multiplier: 1.10),
        City(name: "Taipei", country: "Taiwan", multiplier: 0.65),
        City(name: "Bangkok", country: "Thailand", multiplier: 0.45),
        City(name: "Chiang Mai", country: "Thailand", multiplier: 0.35),
        City(name: "Hanoi", country: "Vietnam", multiplier: 0.32),
        City(name: "Ho Chi Minh City", country: "Vietnam", multiplier: 0.35),
        City(name: "Bali", country: "Indonesia", multiplier: 0.40),
        City(name: "Kuala Lumpur", country: "Malaysia", multiplier: 0.45),
        City(name: "Delhi", country: "India", multiplier: 0.35),
        City(name: "Mumbai", country: "India", multiplier: 0.40),
        City(name: "Dubai", country: "UAE", multiplier: 1.10),

        // Oceania
        City(name: "Sydney", country: "Australia", multiplier: 1.20),
        City(name: "Melbourne", country: "Australia", multiplier: 1.12),
        City(name: "Auckland", country: "New Zealand", multiplier: 1.05),
        City(name: "Queenstown", country: "New Zealand", multiplier: 1.15),

        // Latin America
        City(name: "Mexico City", country: "Mexico", multiplier: 0.55),
        City(name: "Oaxaca", country: "Mexico", multiplier: 0.45),
        City(name: "Tulum", country: "Mexico", multiplier: 0.80),
        City(name: "Buenos Aires", country: "Argentina", multiplier: 0.50),
        City(name: "Santiago", country: "Chile", multiplier: 0.62),
        City(name: "Lima", country: "Peru", multiplier: 0.48),
        City(name: "Bogota", country: "Colombia", multiplier: 0.45),
        City(name: "Medellin", country: "Colombia", multiplier: 0.42),
        City(name: "Rio de Janeiro", country: "Brazil", multiplier: 0.55),
        City(name: "San Jose", country: "Costa Rica", multiplier: 0.70),

        // Africa and Middle East
        City(name: "Cape Town", country: "South Africa", multiplier: 0.50),
        City(name: "Marrakesh", country: "Morocco", multiplier: 0.45),
        City(name: "Cairo", country: "Egypt", multiplier: 0.35),
        City(name: "Nairobi", country: "Kenya", multiplier: 0.45),
        City(name: "Tel Aviv", country: "Israel", multiplier: 1.25),
    ]

    static func search(_ query: String) -> [City] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return cities }
        return cities.filter {
            $0.name.lowercased().contains(trimmed) || $0.country.lowercased().contains(trimmed)
        }
    }

    static func city(named name: String) -> City? {
        cities.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Plain-language comparison, used under the forecast.
    static func comparison(for multiplier: Double) -> String {
        let percent = Int(((multiplier - 1) * 100).rounded())
        if percent == 0 { return "about the same as \(baseline)" }
        return percent > 0
            ? "\(percent)% more than \(baseline)"
            : "\(abs(percent))% less than \(baseline)"
    }
}
