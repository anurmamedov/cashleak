import AuthenticationServices
import Combine
import CryptoKit
import FirebaseAuth
import FirebaseCore
import Foundation
import Security

@MainActor
final class AuthenticationService: ObservableObject {

    @Published private(set) var user: FirebaseAuth.User?
    @Published private(set) var isReady = false

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
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        let change = result.user.createProfileChangeRequest()
        change.displayName = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        try await change.commitChanges()
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

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idToken,
            rawNonce: rawNonce,
            fullName: credential.fullName
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

    var errorDescription: String? {
        switch self {
        case .missingAppleIdentityToken:
            "Apple didn't return a valid identity token. Please try again."
        }
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
