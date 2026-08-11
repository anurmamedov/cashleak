import Foundation
import SwiftUI

/// User preferences that don't belong in the SwiftData store.
///
/// These are device-level display choices, not data. Putting them in CloudKit
/// would mean an accent colour change syncing across devices, which is more
/// surprising than useful.
enum AppSettings {

    private enum Key {
        static let currencyCode = "settings.currencyCode"
        static let accentHex = "settings.accentHex"
        static let notificationHour = "settings.notificationHour"
        static let notificationMinute = "settings.notificationMinute"
        static let notificationsEnabled = "settings.notificationsEnabled"
    }

    /// Defaults to the device's own currency. Hardcoding CAD meant every user
    /// outside Canada saw the wrong symbol on every screen.
    static var currencyCode: String {
        get {
            UserDefaults.standard.string(forKey: Key.currencyCode)
                ?? Locale.current.currency?.identifier
                ?? "CAD"
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.currencyCode) }
    }

    /// Coral by default — the leak accent.
    static var accentHex: String {
        get { UserDefaults.standard.string(forKey: Key.accentHex) ?? AccentOption.coral.hex }
        set { UserDefaults.standard.set(newValue, forKey: Key.accentHex) }
    }

    static var notificationHour: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: Key.notificationHour)
            return stored == 0 && !UserDefaults.standard.hasValue(Key.notificationHour) ? 21 : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.notificationHour) }
    }

    static var notificationMinute: Int {
        get { UserDefaults.standard.integer(forKey: Key.notificationMinute) }
        set { UserDefaults.standard.set(newValue, forKey: Key.notificationMinute) }
    }

    static var notificationsEnabled: Bool {
        get {
            UserDefaults.standard.hasValue(Key.notificationsEnabled)
                ? UserDefaults.standard.bool(forKey: Key.notificationsEnabled)
                : true
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.notificationsEnabled) }
    }

    /// Common currencies offered in settings. The device default is always
    /// included even when it isn't on this list.
    static let offeredCurrencies = ["CAD", "USD", "EUR", "GBP", "AUD", "NZD", "CHF", "SEK", "JPY"]
}

private extension UserDefaults {
    func hasValue(_ key: String) -> Bool {
        object(forKey: key) != nil
    }
}

/// The user-selectable accent.
///
/// One accent at a time. The leak colour changes with it; teal for "worth it"
/// and green for improvement stay fixed, because those carry meaning rather
/// than personality.
enum AccentOption: String, CaseIterable, Identifiable {
    case coral, blue, purple, pink

    var id: String { rawValue }

    var hex: String {
        switch self {
        case .coral: "D85A30"
        case .blue: "378ADD"
        case .purple: "7F77DD"
        case .pink: "D4537E"
        }
    }

    var name: String {
        switch self {
        case .coral: "Coral"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        }
    }
}
