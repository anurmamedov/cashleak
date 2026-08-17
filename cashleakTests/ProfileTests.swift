import XCTest
import SwiftData
@testable import cashleak

/// Registration validation and the separate local app lock.
/// Firebase integration is exercised by the app; these tests cover pure local
/// validation and hashing behavior.
final class ProfileTests: XCTestCase {

    private func failures(
        first: String = "Anar",
        last: String = "Nur",
        email: String = "anar@example.com",
        password: String = "longenough",
        confirm: String? = nil
    ) -> [ProfileValidator.Failure] {
        ProfileValidator.validateRegistration(
            firstName: first, lastName: last, email: email,
            password: password, confirmPassword: confirm ?? password
        )
    }

    // MARK: Required fields

    func testValidRegistrationPasses() {
        XCTAssertTrue(failures().isEmpty)
    }

    func testFirstNameIsRequired() {
        XCTAssertTrue(failures(first: "").contains(.firstNameMissing))
        XCTAssertTrue(failures(first: "   ").contains(.firstNameMissing))
    }

    func testLastNameIsRequired() {
        XCTAssertTrue(failures(last: "").contains(.lastNameMissing))
    }

    func testEmailIsRequired() {
        XCTAssertTrue(failures(email: "").contains(.emailMissing))
    }

    func testAllFailuresReportTogether() {
        let found = failures(first: "", last: "", email: "", password: "x", confirm: "y")
        XCTAssertTrue(found.contains(.firstNameMissing))
        XCTAssertTrue(found.contains(.lastNameMissing))
        XCTAssertTrue(found.contains(.emailMissing))
        XCTAssertTrue(found.contains(.passwordTooShort))
        XCTAssertTrue(found.contains(.passwordMismatch))
    }

    // MARK: Email

    func testAcceptsOrdinaryAddresses() {
        for address in [
            "a@b.co", "anar.nur@example.com", "first+tag@sub.domain.org",
            "UPPER@EXAMPLE.COM", "x_y-z@example.co.uk",
        ] {
            XCTAssertTrue(ProfileValidator.isValidEmail(address), address)
        }
    }

    func testRejectsMalformedAddresses() {
        for address in [
            "no-at-sign", "@example.com", "user@", "user@nodot",
            "two@@example.com", "user name@example.com", "user@.com", "user@com.",
        ] {
            XCTAssertFalse(ProfileValidator.isValidEmail(address), address)
        }
    }

    /// Deliberately permissive — Firebase performs final validation.
    func testDoesNotOverReject() {
        XCTAssertTrue(ProfileValidator.isValidEmail("weird!but#legal@example.com"))
    }

    // MARK: Password

    func testPasswordMinimumLength() {
        XCTAssertTrue(failures(password: "short").contains(.passwordTooShort))
        XCTAssertFalse(failures(password: "12345678").contains(.passwordTooShort))
    }

    func testPasswordsMustMatch() {
        XCTAssertTrue(failures(password: "longenough", confirm: "different1").contains(.passwordMismatch))
    }

    // MARK: Hashing

    /// The password itself must never be derivable from what's stored.
    func testHashIsNotThePassword() {
        let salt = AppLock.makeSalt()
        let digest = AppLock.hash(password: "hunter2000", salt: salt)

        XCTAssertEqual(digest.count, 32)
        XCTAssertFalse(String(decoding: digest, as: UTF8.self).contains("hunter"))
    }

    func testSameInputProducesSameHash() {
        let salt = AppLock.makeSalt()
        XCTAssertEqual(
            AppLock.hash(password: "correct horse", salt: salt),
            AppLock.hash(password: "correct horse", salt: salt)
        )
    }

    /// Without a per-install salt, two users with the same password would have
    /// identical stored hashes.
    func testDifferentSaltsProduceDifferentHashes() {
        let a = AppLock.hash(password: "same password", salt: AppLock.makeSalt())
        let b = AppLock.hash(password: "same password", salt: AppLock.makeSalt())
        XCTAssertNotEqual(a, b)
    }

    func testDifferentPasswordsProduceDifferentHashes() {
        let salt = AppLock.makeSalt()
        XCTAssertNotEqual(
            AppLock.hash(password: "password one", salt: salt),
            AppLock.hash(password: "password two", salt: salt)
        )
    }

    func testSaltsAreRandomAndLongEnough() {
        let salts = (0..<20).map { _ in AppLock.makeSalt() }
        XCTAssertEqual(Set(salts).count, 20)
        XCTAssertTrue(salts.allSatisfy { $0.count == 32 })
    }

    // MARK: Sign in with Apple

    func testAppleNonceHasRequestedLengthAndIsRandom() {
        let first = AppleSignInNonce.make(length: 32)
        let second = AppleSignInNonce.make(length: 32)

        XCTAssertEqual(first.count, 32)
        XCTAssertEqual(second.count, 32)
        XCTAssertNotEqual(first, second)
    }

    func testAppleNonceHashUsesSHA256() {
        XCTAssertEqual(
            AppleSignInNonce.hash("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }
}

/// The profile model itself.
@MainActor
final class UserProfileTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try TestSupport.makeContainer()
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        container = nil
        context = nil
    }

    func testFullNameJoinsBothParts() {
        let profile = UserProfile(firstName: "Anar", lastName: "Nur", email: "a@b.co")
        XCTAssertEqual(profile.fullName, "Anar Nur")
    }

    /// Sign in with Apple can withhold the name entirely, so an empty half must
    /// not leave a stray space.
    func testFullNameHandlesMissingHalves() {
        XCTAssertEqual(UserProfile(firstName: "Anar", lastName: "", email: "").fullName, "Anar")
        XCTAssertEqual(UserProfile(firstName: "", lastName: "Nur", email: "").fullName, "Nur")
        XCTAssertEqual(UserProfile(firstName: "", lastName: "", email: "").fullName, "")
    }

    func testInitialsFallBackWhenNameIsMissing() {
        XCTAssertEqual(UserProfile(firstName: "Anar", lastName: "Nur", email: "").initials, "AN")
        XCTAssertEqual(UserProfile(firstName: "", lastName: "", email: "").initials, "?")
    }

    func testAppleProfileStoresTheUserIdentifier() throws {
        let profile = UserProfile(
            firstName: "Anar", lastName: "Nur", email: "a@b.co",
            signInMethod: .apple, appleUserID: "001234.abcdef"
        )
        context.insert(profile)
        try context.save()

        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<UserProfile>()).first)
        XCTAssertEqual(stored.signInMethod, .apple)
        XCTAssertEqual(stored.appleUserID, "001234.abcdef")
    }

    func testUnknownSignInMethodFallsBackToEmail() {
        let profile = UserProfile(firstName: "A", lastName: "B", email: "a@b.co")
        profile.signInMethodRaw = "somethingFromLater"
        XCTAssertEqual(profile.signInMethod, .email)
    }

    /// Signing out removes the profile. It must not take the transactions with
    /// it — the data was never owned by an account.
    func testDeletingProfileLeavesTransactionsIntact() throws {
        let profile = UserProfile(firstName: "Anar", lastName: "Nur", email: "a@b.co")
        let transaction = TestSupport.confirmed(40, verdict: .leak)
        context.insert(profile)
        context.insert(transaction)
        try context.save()

        context.delete(profile)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<UserProfile>()).isEmpty)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Transaction>()).count, 1)
    }
}
