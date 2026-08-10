import XCTest
@testable import cashleak

/// The highest-value test file in the project.
///
/// Normalization feeds the dedup matcher, and a dedup failure doubles someone's
/// totals — which is the one bug a spending app cannot survive.
final class MerchantNormalizerTests: XCTestCase {

    // MARK: Normalization

    func testStripsProcessorPrefixes() {
        XCTAssertEqual(MerchantNormalizer.normalize("SQ *BLUE BOTTLE"), "blue bottle")
        XCTAssertEqual(MerchantNormalizer.normalize("TST* TERRONI"), "terroni")
        XCTAssertEqual(MerchantNormalizer.normalize("PP*SPOTIFY"), "spotify")
    }

    func testStripsStoreNumbers() {
        XCTAssertEqual(MerchantNormalizer.normalize("LOBLAWS #1043"), "loblaws")
        XCTAssertEqual(MerchantNormalizer.normalize("TIM HORTONS 4471"), "tim hortons")
    }

    func testStripsTrailingProvinceAndEntitySuffixes() {
        XCTAssertEqual(MerchantNormalizer.normalize("METRO TORONTO ON"), "metro toronto")
        XCTAssertEqual(MerchantNormalizer.normalize("ACME HOLDINGS INC"), "acme holdings")
    }

    /// "co" at the end is noise; "co" inside a name is part of it.
    func testKeepsMeaningfulTokensMidName() {
        XCTAssertEqual(MerchantNormalizer.normalize("CO OP GROCERY"), "co op grocery")
    }

    func testCollapsesPunctuationAndWhitespace() {
        XCTAssertEqual(MerchantNormalizer.normalize("UBER   EATS"), "uber eats")
        XCTAssertEqual(MerchantNormalizer.normalize("PRESTO/METROLINX"), "presto metrolinx")
    }

    func testEmptyAndGarbageInputsDoNotCrash() {
        XCTAssertEqual(MerchantNormalizer.normalize(""), "")
        XCTAssertEqual(MerchantNormalizer.normalize("###"), "")
        XCTAssertEqual(MerchantNormalizer.normalize("12345"), "")
    }

    func testFixtureCorpus() {
        for fixture in TestSupport.merchantFixtures {
            XCTAssertEqual(
                MerchantNormalizer.normalize(fixture.raw),
                fixture.expected,
                "normalizing \(fixture.raw)"
            )
        }
    }

    // MARK: Fuzzy matching

    func testMatchesSameMerchantAcrossFormats() {
        let a = MerchantNormalizer.normalize("SQ *BLUE BOTTLE COFFEE")
        let b = MerchantNormalizer.normalize("BLUE BOTTLE #4412")
        XCTAssertTrue(MerchantNormalizer.isFuzzyMatch(a, b))
    }

    func testMatchesTruncatedNames() {
        XCTAssertTrue(MerchantNormalizer.isFuzzyMatch("tim hortons", "tim horton"))
    }

    /// The failure that matters most: merging two genuinely different places.
    /// A false positive silently deletes a real transaction from the user's
    /// totals, and they have no way to notice.
    func testDoesNotMatchDifferentMerchants() {
        XCTAssertFalse(MerchantNormalizer.isFuzzyMatch("loblaws", "metro"))
        XCTAssertFalse(MerchantNormalizer.isFuzzyMatch("shell", "esso"))
        XCTAssertFalse(MerchantNormalizer.isFuzzyMatch("uber eats", "uber"))
    }

    func testEmptyNeverMatches() {
        XCTAssertFalse(MerchantNormalizer.isFuzzyMatch("", ""))
        XCTAssertFalse(MerchantNormalizer.isFuzzyMatch("loblaws", ""))
    }

    // MARK: Levenshtein

    func testLevenshteinBasics() {
        XCTAssertEqual(MerchantNormalizer.levenshtein("", ""), 0)
        XCTAssertEqual(MerchantNormalizer.levenshtein("abc", "abc"), 0)
        XCTAssertEqual(MerchantNormalizer.levenshtein("abc", ""), 3)
        XCTAssertEqual(MerchantNormalizer.levenshtein("kitten", "sitting"), 3)
    }

    func testLevenshteinIsSymmetric() {
        XCTAssertEqual(
            MerchantNormalizer.levenshtein("loblaws", "loblaw"),
            MerchantNormalizer.levenshtein("loblaw", "loblaws")
        )
    }
}
