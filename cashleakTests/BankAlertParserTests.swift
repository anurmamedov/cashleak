import XCTest
@testable import cashleak

/// The half of L2 that doesn't need a phone.
///
/// These tests prove the parser handles the alert shapes we expect. They do
/// **not** prove Shortcuts hands us a message body, and they don't prove the
/// templates match what any real bank sends — both still need L2 on device.
final class BankAlertParserTests: XCTestCase {

    // MARK: Rejection — the dangerous direction

    /// A balance parsed as spending puts a large fictional number in the
    /// month's totals. Rejecting these matters more than parsing purchases.
    func testRejectsBalanceAlerts() {
        XCTAssertNil(BankAlertParser.parse("RBC: Your available balance is $2,481.19."))
        XCTAssertNil(BankAlertParser.parse("TD: Available funds: $980.00"))
    }

    func testRejectsDeposits() {
        XCTAssertNil(BankAlertParser.parse("TD: A deposit of $1,200.00 has been made."))
        XCTAssertNil(BankAlertParser.parse("Interac e-Transfer received: $50.00"))
    }

    func testRejectsDeclinesAndRefunds() {
        XCTAssertNil(BankAlertParser.parse("CIBC: A purchase of $60.00 at SHELL was declined."))
        XCTAssertNil(BankAlertParser.parse("BMO: A refund of $25.00 from AMAZON was processed."))
    }

    /// One-time codes are the most common bank SMS of all.
    func testRejectsVerificationCodes() {
        XCTAssertNil(BankAlertParser.parse("Scotiabank: Your verification code is 884120."))
        XCTAssertNil(BankAlertParser.parse("Your one-time password is 4471."))
    }

    func testRejectsMessagesWithNoAmount() {
        XCTAssertNil(BankAlertParser.parse("RBC: Your statement is ready to view."))
        XCTAssertNil(BankAlertParser.parse("Hello, are we still on for dinner?"))
    }

    func testRejectsImplausiblyLargeAmounts() {
        XCTAssertNil(BankAlertParser.parse("RBC: A purchase of $250,000.00 was made at CAR DEALER."))
    }

    // MARK: Amounts

    func testExtractsAmountWithSymbol() {
        XCTAssertEqual(BankAlertParser.extractAmount(from: "purchase of $34.20 at X"), 34.20)
    }

    func testExtractsAmountWithCurrencyCode() {
        XCTAssertEqual(BankAlertParser.extractAmount(from: "Purchase of CAD 88.40 at Y"), 88.40)
        XCTAssertEqual(BankAlertParser.extractAmount(from: "amount: 42.10 CAD"), 42.10)
    }

    func testExtractsAmountWithThousandsSeparator() {
        XCTAssertEqual(BankAlertParser.extractAmount(from: "purchase of $1,299.99 at Z"), 1299.99)
    }

    /// Card digits, reference numbers and dates are all numbers. Anchoring on a
    /// currency marker is what stops the parser returning one of them.
    func testIgnoresCardDigitsAndReferences() {
        XCTAssertEqual(
            BankAlertParser.extractAmount(from: "card ending 6411 ref 99213 purchase $12.50"),
            12.50
        )
    }

    func testReturnsNilWhenNoCurrencyMarker() {
        XCTAssertNil(BankAlertParser.extractAmount(from: "card ending 6411 on Aug 12"))
    }

    // MARK: Merchants

    func testExtractsMerchantAfterAt() {
        XCTAssertEqual(
            BankAlertParser.extractMerchant(from: "A purchase of $34.20 was made at UBER EATS on your card."),
            "UBER EATS"
        )
    }

    func testExtractsMerchantWithStoreNumber() {
        XCTAssertEqual(
            BankAlertParser.extractMerchant(from: "Purchase of CAD 88.40 at LOBLAWS #1043 on card."),
            "LOBLAWS #1043"
        )
    }

    func testExtractsMerchantBeforePunctuation() {
        XCTAssertEqual(
            BankAlertParser.extractMerchant(from: "Scotiabank alert: $6.75 charged at TIM HORTONS 4471."),
            "TIM HORTONS 4471"
        )
    }

    /// "at 4:15pm" and "at 6411" are not merchants.
    func testDoesNotReturnBareNumbersAsMerchants() {
        XCTAssertNil(BankAlertParser.extractMerchant(from: "purchase of $10.00 at 6411"))
    }

    // MARK: End to end

    func testParsesEverySamplePurchase() {
        for sample in BankAlertParser.sampleAlerts where sample.shouldParse {
            let result = BankAlertParser.parse(sample.text)
            XCTAssertNotNil(result, "\(sample.bank) failed to parse: \(sample.text)")
            XCTAssertGreaterThan(result?.amount ?? 0, 0, sample.bank)
        }
    }

    func testRejectsEveryNonPurchaseSample() {
        for sample in BankAlertParser.sampleAlerts where !sample.shouldParse {
            XCTAssertNil(
                BankAlertParser.parse(sample.text),
                "\(sample.bank) should have been rejected: \(sample.text)"
            )
        }
    }

    func testConfidenceReflectsWhatWasFound() {
        let full = BankAlertParser.parse("RBC: A purchase of $34.20 was made at UBER EATS on your card.")
        XCTAssertEqual(full?.confidence, .high)
        XCTAssertEqual(full?.merchant, "UBER EATS")

        let amountOnly = BankAlertParser.parse("RBC: Transaction of $34.20 completed.")
        XCTAssertEqual(amountOnly?.confidence, .medium)
        XCTAssertNil(amountOnly?.merchant)
    }

    // MARK: Presets

    func testPresetsCoverTheMajorCanadianBanks() {
        let banks = Set(BankAlertParser.presets.map(\.bank))
        for expected in ["RBC", "TD", "Scotiabank", "BMO", "CIBC", "Tangerine"] {
            XCTAssertTrue(banks.contains(expected), expected)
        }
    }

    func testPresetPhrasesAreNotEmpty() {
        XCTAssertTrue(BankAlertParser.presets.allSatisfy { !$0.containsPhrase.isEmpty })
    }
}
