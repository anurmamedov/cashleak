import XCTest
import SwiftUI
@testable import cashleak

/// The ramp encodes product decisions, so these tests are guarding intent
/// rather than arithmetic. Each one corresponds to a rule in plan.md.
final class LeakRampTests: XCTestCase {

    // MARK: Insufficient data

    /// A single early leak would otherwise read as 100% and paint the card at
    /// its darkest on day one.
    func testHoldsPalestShadeBelowThreshold() {
        let sparse = LeakRamp.color(
            ratio: 1.0,
            transactionCount: 1,
            daysOfHistory: 1,
            colorScheme: .light
        )
        let floor = LeakRamp.color(
            ratio: 0.0,
            transactionCount: 1,
            daysOfHistory: 1,
            colorScheme: .light
        )
        XCTAssertEqual(sparse.description, floor.description)
    }

    func testTenTransactionsUnlocksTheRamp() {
        XCTAssertFalse(LeakRamp.hasMeaningfulData(transactionCount: 9, daysOfHistory: 1))
        XCTAssertTrue(LeakRamp.hasMeaningfulData(transactionCount: 10, daysOfHistory: 1))
    }

    /// Either condition is enough — a week of light use counts as much as a
    /// busy day.
    func testAWeekOfHistoryAlsoUnlocksTheRamp() {
        XCTAssertFalse(LeakRamp.hasMeaningfulData(transactionCount: 2, daysOfHistory: 6))
        XCTAssertTrue(LeakRamp.hasMeaningfulData(transactionCount: 2, daysOfHistory: 7))
    }

    // MARK: Direction

    func testDeepensAsRatioRisesInLightMode() {
        let pale = components(ratio: 0.05, scheme: .light)
        let mid = components(ratio: 0.30, scheme: .light)
        let deep = components(ratio: 0.60, scheme: .light)

        XCTAssertGreaterThan(pale.brightness, mid.brightness)
        XCTAssertGreaterThan(mid.brightness, deep.brightness)
    }

    /// Dark mode inverts — deepening means going lighter, or the card
    /// disappears into the background exactly when it should be loudest.
    func testLightensAsRatioRisesInDarkMode() {
        let pale = components(ratio: 0.05, scheme: .dark)
        let mid = components(ratio: 0.30, scheme: .dark)
        let deep = components(ratio: 0.60, scheme: .dark)

        XCTAssertLessThan(pale.brightness, mid.brightness)
        XCTAssertLessThan(mid.brightness, deep.brightness)
    }

    // MARK: Continuity

    /// Interpolation is continuous, so a small change in ratio must never
    /// produce a visible jump.
    func testNoSnappingBetweenBands() {
        let below = components(ratio: 0.249, scheme: .light)
        let above = components(ratio: 0.251, scheme: .light)
        XCTAssertEqual(below.brightness, above.brightness, accuracy: 0.02)
    }

    func testClampsOutOfRangeRatios() {
        let negative = components(ratio: -0.5, scheme: .light)
        let zero = components(ratio: 0, scheme: .light)
        XCTAssertEqual(negative.brightness, zero.brightness, accuracy: 0.001)

        let over = components(ratio: 2.0, scheme: .light)
        let one = components(ratio: 1.0, scheme: .light)
        XCTAssertEqual(over.brightness, one.brightness, accuracy: 0.001)
    }

    // MARK: Hex

    func testHexParsing() {
        let coral = UIColor(Color(hex: "D85A30"))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        coral.getRed(&r, green: &g, blue: &b, alpha: &a)

        XCTAssertEqual(Double(r), 216.0 / 255, accuracy: 0.01)
        XCTAssertEqual(Double(g), 90.0 / 255, accuracy: 0.01)
        XCTAssertEqual(Double(b), 48.0 / 255, accuracy: 0.01)
    }

    func testMixReturnsEndpoints() {
        let a = Color(hex: "000000")
        let b = Color(hex: "FFFFFF")
        XCTAssertEqual(brightness(a.mixed(with: b, amount: 0)), 0, accuracy: 0.01)
        XCTAssertEqual(brightness(a.mixed(with: b, amount: 1)), 1, accuracy: 0.01)
        XCTAssertEqual(brightness(a.mixed(with: b, amount: 0.5)), 0.5, accuracy: 0.02)
    }

    // MARK: Helpers

    private func components(ratio: Double, scheme: ColorScheme) -> (brightness: Double, color: Color) {
        let color = LeakRamp.color(
            ratio: ratio,
            transactionCount: 50,
            daysOfHistory: 30,
            colorScheme: scheme
        )
        return (brightness(color), color)
    }

    private func brightness(_ color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        // Perceptual luminance — a plain RGB average would call pure blue and
        // pure yellow equally bright.
        return Double(0.299 * r + 0.587 * g + 0.114 * b)
    }
}

// MARK: - Contrast

/// The card's text has to be readable at every point on the ramp.
///
/// These exist because it wasn't. `color` honoured the minimum-data gate and
/// `foreground` didn't, so a first week containing one leak produced ratio 1.0:
/// the background held at the palest stop while the text switched to the
/// light-on-dark branch. Both were `FAECE7`. The card looked empty on a real
/// phone and every existing test passed.
extension LeakRampTests {

    private func rgb(_ c: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b)
    }

    /// Rough perceptual distance. Not WCAG — just enough to catch "identical".
    private func distance(_ a: Color, _ b: Color) -> CGFloat {
        let x = rgb(a), y = rgb(b)
        return abs(x.r - y.r) + abs(x.g - y.g) + abs(x.b - y.b)
    }

    func testTextIsNeverTheSameColourAsTheCard() {
        for scheme in [ColorScheme.light, .dark] {
            for count in [0, 1, 5, 9, 10, 50] {
                for days in [0, 1, 6, 7, 30] {
                    for ratio in stride(from: 0.0, through: 1.0, by: 0.05) {
                        let bg = LeakRamp.color(
                            ratio: ratio, transactionCount: count,
                            daysOfHistory: days, colorScheme: scheme
                        )
                        let fg = LeakRamp.foreground(
                            ratio: ratio, transactionCount: count,
                            daysOfHistory: days, colorScheme: scheme
                        )
                        XCTAssertGreaterThan(
                            distance(bg, fg), 0.5,
                            "\(scheme) ratio \(ratio) count \(count) days \(days): text too close to card"
                        )
                    }
                }
            }
        }
    }

    /// The exact case from the device: one leak in the first few days.
    func testFirstWeekWithEverythingLeakedStaysReadable() {
        for scheme in [ColorScheme.light, .dark] {
            let bg = LeakRamp.color(
                ratio: 1.0, transactionCount: 2, daysOfHistory: 1, colorScheme: scheme
            )
            let fg = LeakRamp.foreground(
                ratio: 1.0, transactionCount: 2, daysOfHistory: 1, colorScheme: scheme
            )
            XCTAssertNotEqual(rgb(bg).r, rgb(fg).r, accuracy: 0.0, "\(scheme): card and text identical")
            XCTAssertGreaterThan(distance(bg, fg), 1.0, "\(scheme): needs strong contrast at the palest stop")
        }
    }

    /// Once there is enough history, the text must flip with the card.
    func testForegroundFlipsOnceTheRampIsLive() {
        let pale = LeakRamp.foreground(
            ratio: 0.10, transactionCount: 50, daysOfHistory: 30, colorScheme: .light
        )
        let deep = LeakRamp.foreground(
            ratio: 0.70, transactionCount: 50, daysOfHistory: 30, colorScheme: .light
        )
        XCTAssertGreaterThan(distance(pale, deep), 1.0, "dark text on pale, light text on deep")
    }
}
