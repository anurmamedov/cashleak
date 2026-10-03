import Foundation
import LocalAuthentication
import Security

/// The email and password behind "Sign in with Face ID".
///
/// Face ID can't sign anyone in by itself — it proves the person holding the
/// phone is its owner, not which account they have. So the first sign-in on a
/// phone uses the password, and with "Use Face ID next time" on, the password
/// is kept here for the next one (D-024).
///
/// How it's kept:
/// - In the Keychain, bound to **the current Face ID enrolment**
///   (`.biometryCurrentSet`). Reading it shows the Face ID prompt; adding a new
///   face to the phone makes it unreadable, which is the point.
/// - `WhenPasscodeSetThisDeviceOnly`: never in iCloud Keychain, never in a
///   backup, gone if the phone's passcode is removed.
/// - Never leaves the device, and goes nowhere but `Auth.signIn`.
///
/// The email alone sits in `UserDefaults` so the screen can fill it in and
/// show the Face ID button without asking for Face ID first. An email is not a
/// secret; the password is.
/// `nonisolated` because the project defaults everything to the main actor,
/// and the Keychain read has to run off it — it blocks while the Face ID sheet
/// is up. Keychain and `UserDefaults` are both safe from any thread.
nonisolated enum SavedSignIn {

    private static let service = "com.karasandlabs.cashleak.signin"
    private static let emailKey = "signin.savedEmail"

    /// The email a password is saved for, if any.
    static var savedEmail: String? {
        UserDefaults.standard.string(forKey: emailKey)
    }

    /// Whether "Sign in with Face ID" can be offered right now.
    static var isAvailable: Bool {
        savedEmail != nil && biometryIsAvailable
    }

    static var biometryIsAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Saves the sign-in, replacing any earlier one. Doesn't prompt — the
    /// protection applies when it's read.
    @discardableResult
    static func save(email: String, password: String) -> Bool {
        forget()

        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email,
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessControl as String: access,
        ]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { return false }

        UserDefaults.standard.set(email, forKey: emailKey)
        return true
    }

    enum LoadResult {
        case success(email: String, password: String)
        /// Face ID was cancelled or failed. Nothing is wrong with the saved
        /// sign-in; the password field is the way forward.
        case cancelled
        /// The saved sign-in can't be read any more — a new face was enrolled,
        /// or the passcode was removed. It's been forgotten.
        case unavailable
    }

    /// Shows Face ID and reads the saved password.
    ///
    /// Runs off the main thread: the Keychain read blocks while the Face ID
    /// sheet is up.
    static func load() async -> LoadResult {
        guard let email = savedEmail else { return .unavailable }

        return await Task.detached(priority: .userInitiated) { () -> LoadResult in
            let context = LAContext()
            context.localizedReason = "Sign in to CashLeak"
            context.localizedFallbackTitle = ""

            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: email,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecUseAuthenticationContext as String: context,
            ]

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            switch status {
            case errSecSuccess:
                guard let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
                    forget()
                    return .unavailable
                }
                return .success(email: email, password: password)
            case errSecUserCanceled, errSecAuthFailed:
                return .cancelled
            default:
                // errSecItemNotFound after a Face ID change, or anything else
                // that means this saved sign-in will never work again.
                forget()
                return .unavailable
            }
        }.value
    }

    static func forget() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
        UserDefaults.standard.removeObject(forKey: emailKey)
    }
}
