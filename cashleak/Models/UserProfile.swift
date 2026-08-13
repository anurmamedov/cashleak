import Foundation
import SwiftData

/// Who's using the app.
///
/// **There is no account.** This profile exists only on the device and in the
/// user's own iCloud — there's no CashLeak server to register with, nothing is
/// transmitted, and no password is stored anywhere we can read. See D-012.
///
/// It exists to personalise the app and to hold the identity returned by Sign
/// in with Apple, not to authenticate against anything.
@Model
final class UserProfile {

    var firstName: String = ""
    var lastName: String = ""
    var email: String = ""

    /// `apple` or `email`. Stored as a raw string for the same reason the other
    /// enums are — reordering cases must never remap existing records.
    var signInMethodRaw: String = SignInMethod.email.rawValue

    /// Apple's stable, app-specific user identifier. Never an Apple ID, never
    /// an email — Apple deliberately doesn't hand those over on repeat sign-ins.
    var appleUserID: String?

    var createdAt: Date = Date.distantPast

    var signInMethod: SignInMethod {
        get { SignInMethod(rawValue: signInMethodRaw) ?? .email }
        set { signInMethodRaw = newValue.rawValue }
    }

    var fullName: String {
        [firstName, lastName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var initials: String {
        let first = firstName.first.map(String.init) ?? ""
        let last = lastName.first.map(String.init) ?? ""
        let combined = (first + last).uppercased()
        return combined.isEmpty ? "?" : combined
    }

    init(
        firstName: String,
        lastName: String,
        email: String,
        signInMethod: SignInMethod = .email,
        appleUserID: String? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.signInMethodRaw = signInMethod.rawValue
        self.appleUserID = appleUserID
        self.createdAt = .now
    }
}

enum SignInMethod: String, Codable, CaseIterable, Sendable {
    case apple
    case email

    var displayName: String {
        switch self {
        case .apple: "Apple"
        case .email: "Email"
        }
    }
}

/// Field validation for the registration form.
///
/// Pure and static so the rules are testable without a view.
enum ProfileValidator {

    enum Failure: String, Equatable {
        case firstNameMissing
        case lastNameMissing
        case emailMissing
        case emailMalformed
        case passwordTooShort
        case passwordMismatch
    }

    static let minimumPasswordLength = 8

    static func validateRegistration(
        firstName: String,
        lastName: String,
        email: String,
        password: String,
        confirmPassword: String
    ) -> [Failure] {

        var failures: [Failure] = []

        if firstName.trimmingCharacters(in: .whitespaces).isEmpty {
            failures.append(.firstNameMissing)
        }
        if lastName.trimmingCharacters(in: .whitespaces).isEmpty {
            failures.append(.lastNameMissing)
        }

        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        if trimmedEmail.isEmpty {
            failures.append(.emailMissing)
        } else if !isValidEmail(trimmedEmail) {
            failures.append(.emailMalformed)
        }

        if password.count < minimumPasswordLength {
            failures.append(.passwordTooShort)
        }
        if password != confirmPassword {
            failures.append(.passwordMismatch)
        }

        return failures
    }

    /// Deliberately permissive. The address is never sent anywhere, so the only
    /// job here is catching typos — rejecting a valid but unusual address would
    /// be worse than accepting a strange one.
    static func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.contains(" "), trimmed.count >= 5 else { return false }

        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        guard !parts[0].isEmpty, !parts[1].isEmpty else { return false }

        let domain = parts[1]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }

        return true
    }

    static func message(for failure: Failure) -> String {
        switch failure {
        case .firstNameMissing: "First name is needed."
        case .lastNameMissing: "Last name is needed."
        case .emailMissing: "Email is needed."
        case .emailMalformed: "That email doesn't look right."
        case .passwordTooShort: "Use at least \(minimumPasswordLength) characters."
        case .passwordMismatch: "Passwords don't match."
        }
    }
}
