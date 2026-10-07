import XCTest
@testable import cashleak

/// Store numbers come off for display only — Analysis showed
/// "Tim Hortons #5524" as if that location were a different shop.
final class MerchantDisplayNameTests: XCTestCase {

    func testStoreNumbersAreDropped() {
        XCTAssertEqual(MerchantNormalizer.displayName("Tim Hortons #5524"), "Tim Hortons")
        XCTAssertEqual(MerchantNormalizer.displayName("Starbucks Coffee #23090"), "Starbucks Coffee")
        XCTAssertEqual(MerchantNormalizer.displayName("SHOPPERS DRUG MART 1234"), "SHOPPERS DRUG MART")
    }

    func testNamesWithoutNumbersAreUntouched() {
        XCTAssertEqual(MerchantNormalizer.displayName("Terroni"), "Terroni")
        XCTAssertEqual(MerchantNormalizer.displayName("7-Eleven"), "7-Eleven")
        XCTAssertEqual(MerchantNormalizer.displayName("Cafe 22 Queen"), "Cafe 22 Queen")
    }

    func testANameThatIsOnlyANumberIsKept() {
        XCTAssertEqual(MerchantNormalizer.displayName("1234"), "1234")
    }
}
