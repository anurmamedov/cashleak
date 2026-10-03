import AuthenticationServices
import Combine
import CryptoKit
import FirebaseAuth
import FirebaseCore
import Foundation
import Security
import UIKit

@MainActor
final class AuthenticationService: ObservableObject {

    @Published private(set) var user: FirebaseAuth.User?
    @Published private(set) var isReady = false

    /// The name Apple supplied at sign-in, held only long enough to create the
    /// local profile. Apple sends it once, on the first sign-in, and it's no
    /// longer forwarded to the sign-in account (D-029).
    private(set) var pendingAppleName: PersonNameComponents?

    private var listener: AuthStateDidChangeListenerHandle?

    init() {
        FirebaseBootstrap.configureIfNeeded()
        listener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.user = user
            self?.isReady = true
        }
    }

    @discardableResult
    func register(
        email: String,
        password: String,
        firstName: String,
        lastName: String
    ) async throws -> FirebaseAuth.User {
        // The name is not stored with the account (D-029). It lives in the
        // profile on the phone and in the person's iCloud; the sign-in account
        // holds only what signing in needs.
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        user = result.user
        return result.user
    }

    @discardableResult
    func signIn(email: String, password: String) async throws -> FirebaseAuth.User {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        user = result.user
        return result.user
    }

    @discardableResult
    func signInWithApple(
        credential: ASAuthorizationAppleIDCredential,
        rawNonce: String
    ) async throws -> FirebaseAuth.User {
        guard let token = credential.identityToken,
              let idToken = String(data: token, encoding: .utf8) else {
            throw AuthenticationFailure.missingAppleIdentityToken
        }

        pendingAppleName = credential.fullName
        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: nil
        )
        let result = try await Auth.auth().signIn(with: firebaseCredential)
        user = result.user
        return result.user
    }

    func sendPasswordReset(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func signOut() throws {
        try Auth.auth().signOut()
        user = nil
    }

    // MARK: Account

    /// Signed in with Apple rather than an email and password.
    var isAppleAccount: Bool {
        user?.providerData.contains { $0.providerID == "apple.com" } ?? false
    }

    var email: String? { user?.email }

    /// Confirms the password belongs to the signed-in account. Used before
    /// anything sensitive — deleting the account, saving it for Face ID — so a
    /// phone left unlocked can't do either.
    func verifyPassword(_ password: String) async throws {
        guard let user = Auth.auth().currentUser, let email = user.email else {
            throw AuthenticationFailure.notSignedIn
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        _ = try await user.reauthenticate(with: credential)
    }

    /// Starts an email change the safe way: confirm the password, then send a
    /// link to the **new** address. The email only changes once that link is
    /// opened, so a typo can't lock anyone out of their account, and someone
    /// with a borrowed phone can't move the account to their own address.
    ///
    /// After the link is opened the old session ends and the person signs in
    /// with the new email.
    func requestEmailChange(to newEmail: String, password: String) async throws {
        try await verifyPassword(password)
        guard let user = Auth.auth().currentUser else { throw AuthenticationFailure.notSignedIn }
        try await user.sendEmailVerification(beforeUpdatingEmail: newEmail)
    }

    /// Picks up a change made outside the app, such as a confirmed new email.
    func refreshUser() async {
        guard let user = Auth.auth().currentUser else { return }
        try? await user.reload()
        self.user = Auth.auth().currentUser
    }

    /// The account's stored name, from before names stopped being sent.
    var legacyDisplayName: String? { user?.displayName }

    /// Removes a name stored with the account by earlier versions, once the
    /// profile has it. Best effort; a failure leaves things as they were.
    func clearStoredName() async {
        guard let user = Auth.auth().currentUser, user.displayName != nil else { return }
        let change = user.createProfileChangeRequest()
        change.displayName = nil
        try? await change.commitChanges()
    }

    func consumePendingAppleName() -> PersonNameComponents? {
        defer { pendingAppleName = nil }
        return pendingAppleName
    }

    /// Deletes an email account after confirming its password.
    ///
    /// Always confirms first rather than waiting for the "sign in again" error
    /// the delete would raise after a while — one predictable step beats an
    /// error halfway through.
    func deleteEmailAccount(password: String) async throws {
        try await verifyPassword(password)
        guard let user = Auth.auth().currentUser else { throw AuthenticationFailure.notSignedIn }
        try await user.delete()
        self.user = nil
    }

    /// Deletes a Sign in with Apple account.
    ///
    /// Apple requires apps to revoke their Sign in with Apple tokens when an
    /// account is deleted, which needs a fresh authorization code — hence the
    /// Apple sheet just before this runs.
    func deleteAppleAccount(credential: ASAuthorizationAppleIDCredential, rawNonce: String) async throws {
        guard let user = Auth.auth().currentUser else { throw AuthenticationFailure.notSignedIn }
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw AuthenticationFailure.missingAppleIdentityToken
        }
        guard let codeData = credential.authorizationCode,
              let code = String(data: codeData, encoding: .utf8) else {
            throw AuthenticationFailure.missingAppleAuthorizationCode
        }

        let appleCredential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: nil
        )
        _ = try await user.reauthenticate(with: appleCredential)
        try await Auth.auth().revokeToken(withAuthorizationCode: code)
        try await user.delete()
        self.user = nil
    }

    static func message(for error: Error) -> String {
        if let failure = error as? AuthenticationFailure {
            return failure.errorDescription ?? "Authentication didn't complete."
        }
        return (error as NSError).localizedDescription
    }
}

@MainActor
enum FirebaseBootstrap {
    private static var isConfigured = false

    static func configureIfNeeded() {
        guard !isConfigured else { return }
        FirebaseApp.configure()
        isConfigured = true
    }
}

enum AuthenticationFailure: LocalizedError {
    case missingAppleIdentityToken
    case missingAppleAuthorizationCode
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .missingAppleIdentityToken:
            "Apple didn't return a valid identity token. Please try again."
        case .missingAppleAuthorizationCode:
            "Apple didn't confirm the request. Please try again."
        case .notSignedIn:
            "You're not signed in."
        }
    }
}

/// Shows the Apple sheet once more to confirm a sensitive action — deleting a
/// Sign in with Apple account needs a fresh authorization from Apple.
final class AppleReauthentication: NSObject {

    let rawNonce = AppleSignInNonce.make()
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var controller: ASAuthorizationController?

    func run() async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        request.nonce = AppleSignInNonce.hash(rawNonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<ASAuthorizationAppleIDCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }
}

extension AppleReauthentication: @preconcurrency ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            finish(.success(credential))
        } else {
            finish(.failure(AuthenticationFailure.missingAppleIdentityToken))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish(.failure(error))
    }
}

extension AppleReauthentication: @preconcurrency ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

enum AppleSignInNonce {
    static func make(length: Int = 32) -> String {
        precondition(length > 0)
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length

        while remaining > 0 {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                fatalError("Unable to generate a secure Sign in with Apple nonce.")
            }

            for byte in bytes where remaining > 0 {
                guard byte < characters.count else { continue }
                result.append(characters[Int(byte)])
                remaining -= 1
            }
        }

        return result
    }

    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
