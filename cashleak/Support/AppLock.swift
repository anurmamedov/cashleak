import Foundation
import CryptoKit
import LocalAuthentication
import Security

/// Optional passcode for opening the app.
///
/// **This is a device lock, not the Firebase account password.** It proves
/// nothing about account identity — it only decides whether this device opens
/// the app after the user is signed in.
///
/// Because of that, the honest implementation is narrow: a salted SHA-256 hash
/// in the Keychain, never the password itself, and never anything transmitted.
/// If someone can read the Keychain they've already defeated the device
/// passcode, at which point the app lock is the least of it.
///
/// Face ID is offered alongside because on a personal device it's both stronger
/// and less annoying than typing.
enum AppLock {

    private static let service = "com.karasandlabs.cashleak.applock"
    private static let hashAccount = "passwordHash"
    private static let saltAccount = "passwordSalt"
    private static let deviceAccount = "deviceAuthentication"

    // MARK: State

    /// Locked by either method. What the app checks before showing anything.
    static var isEnabled: Bool {
        hasPassword || usesDeviceAuthentication
    }

    /// An app-specific password is set (the original lock, from Profile ›
    /// Passcode). Face ID unlocks it too; the password is its fallback.
    static var hasPassword: Bool {
        read(account: hashAccount) != nil
    }

    /// Face ID with the **iPhone's own passcode** as the fallback — no app
    /// password to invent or forget. This is what the one-time offer after
    /// sign-in turns on, because it's one tap and nothing to remember.
    static var usesDeviceAuthentication: Bool {
        read(account: deviceAccount) != nil
    }

    /// Whether this device can lock with Face ID or its passcode at all. False
    /// only on a phone with no passcode set.
    static var canUseDeviceAuthentication: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    static var biometryIsAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
    }

    /// Face ID, Touch ID, or none — used to label the unlock button correctly.
    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Passcode"
        }
    }

    // MARK: Setting

    @discardableResult
    static func setPassword(_ password: String) -> Bool {
        guard password.count >= ProfileValidator.minimumPasswordLength else { return false }

        let salt = makeSalt()
        let hash = hash(password: password, salt: salt)

        return write(salt, account: saltAccount) && write(hash, account: hashAccount)
    }

    static func removePassword() {
        delete(account: hashAccount)
        delete(account: saltAccount)
    }

    /// Turns on the Face ID lock — but only after Face ID (or the passcode)
    /// succeeds once, so nobody ends up with a lock they can't open.
    static func enableDeviceAuthentication() async -> Bool {
        guard await authenticateWithDevice(reason: "Turn on \(biometryName) for CashLeak") else {
            return false
        }
        return write(Data([1]), account: deviceAccount)
    }

    static func disableDeviceAuthentication() {
        delete(account: deviceAccount)
    }

    // MARK: Checking

    static func verify(_ password: String) -> Bool {
        guard
            let storedHash = read(account: hashAccount),
            let salt = read(account: saltAccount)
        else { return false }

        let candidate = hash(password: password, salt: salt)

        // Constant-time comparison. Overkill for a local lock, but the habit is
        // worth keeping — a timing-variant compare is the kind of thing that
        // gets copied into somewhere it matters.
        guard candidate.count == storedHash.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(candidate, storedHash) { difference |= a ^ b }
        return difference == 0
    }

    static func authenticateWithBiometrics() async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use password"

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return false
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Open CashLeak"
            )
        } catch {
            return false
        }
    }

    /// Face ID, falling back to the iPhone passcode. Never fails for want of
    /// biometrics — a passcode always works — which is what makes it safe to
    /// offer as a one-tap lock.
    static func authenticateWithDevice(reason: String = "Open CashLeak") async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return false
        }
    }

    // MARK: One-time offer

    private static let offerKey = "appLock.deviceAuthenticationOffered"

    /// Whether to ask, once, right after sign-in. Never again after an answer
    /// either way — a question that keeps coming back is nagging.
    static var shouldOfferDeviceAuthentication: Bool {
        !isEnabled
            && canUseDeviceAuthentication
            && !UserDefaults.standard.bool(forKey: offerKey)
    }

    static func markDeviceAuthenticationOffered() {
        UserDefaults.standard.set(true, forKey: offerKey)
    }

    // MARK: Hashing

    static func hash(password: String, salt: Data) -> Data {
        var input = Data(password.utf8)
        input.append(salt)
        return Data(SHA256.hash(data: input))
    }

    static func makeSalt(length: Int = 32) -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes)
    }

    // MARK: Keychain

    @discardableResult
    private static func write(_ data: Data, account: String) -> Bool {
        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Never syncs, never leaves the device, unavailable until first
            // unlock after boot.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static func read(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
