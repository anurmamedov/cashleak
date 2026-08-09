import SwiftUI

/// Maps a leak ratio to the Overview card's background.
///
/// The rules here are product decisions, not styling preferences — see
/// DECISIONS.md and plan.md:
///
/// - Darkness maps to **ratio, never amount**. A dark card for a legitimate
///   large purchase is a punishment, and punished users delete finance apps.
/// - Interpolation is continuous. The four bands are reference points, not
///   steps to snap between.
/// - The palest shade holds until there is meaningful data, or a single early
///   leak reads as 100%.
/// - Dark mode inverts: deepening means going lighter.
enum LeakRamp {

    /// Below this, the ramp stays at its palest regardless of ratio.
    static let minimumTransactions = 10
    static let minimumDays = 7

    /// Coral ramp reference points, palest to deepest.
    private static let lightModeStops: [(ratio: Double, color: Color)] = [
        (0.00, Color(hex: "FAECE7")),
        (0.15, Color(hex: "F5C4B3")),
        (0.25, Color(hex: "F0997B")),
        (0.40, Color(hex: "D85A30")),
        (0.60, Color(hex: "993C1D")),
    ]

    /// Dark mode runs the other way — deeper leak means a lighter card.
    private static let darkModeStops: [(ratio: Double, color: Color)] = [
        (0.00, Color(hex: "3A1810")),
        (0.15, Color(hex: "5C2617")),
        (0.25, Color(hex: "8A3A20")),
        (0.40, Color(hex: "C25330")),
        (0.60, Color(hex: "E8845C")),
    ]

    /// Whether there's enough history for the ramp to mean anything.
    static func hasMeaningfulData(transactionCount: Int, daysOfHistory: Int) -> Bool {
        transactionCount >= minimumTransactions || daysOfHistory >= minimumDays
    }

    static func color(
        ratio: Double,
        transactionCount: Int,
        daysOfHistory: Int,
        colorScheme: ColorScheme
    ) -> Color {
        let stops = colorScheme == .dark ? darkModeStops : lightModeStops

        guard hasMeaningfulData(transactionCount: transactionCount, daysOfHistory: daysOfHistory) else {
            return stops[0].color
        }

        let r = min(max(ratio, 0), 1)

        if r <= stops[0].ratio { return stops[0].color }
        if r >= stops[stops.count - 1].ratio { return stops[stops.count - 1].color }

        for i in 0..<(stops.count - 1) {
            let lower = stops[i], upper = stops[i + 1]
            if r >= lower.ratio && r <= upper.ratio {
                let span = upper.ratio - lower.ratio
                let t = span > 0 ? (r - lower.ratio) / span : 0
                return lower.color.mixed(with: upper.color, amount: t)
            }
        }
        return stops[0].color
    }

    /// Text colour that stays legible across the whole ramp.
    static func foreground(ratio: Double, colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            return ratio >= 0.40 ? Color(hex: "2C1109") : Color(hex: "FAECE7")
        }
        return ratio >= 0.40 ? Color(hex: "FAECE7") : Color(hex: "4A1B0C")
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Linear blend toward another colour. `amount` of 0 returns self.
    func mixed(with other: Color, amount: Double) -> Color {
        let t = min(max(amount, 0), 1)
        let a = UIColor(self), b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(
            .sRGB,
            red: Double(ar + (br - ar) * t),
            green: Double(ag + (bg - ag) * t),
            blue: Double(ab + (bb - ab) * t),
            opacity: Double(aa + (ba - aa) * t)
        )
    }
}
