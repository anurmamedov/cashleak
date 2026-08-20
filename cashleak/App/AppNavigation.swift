import Combine
import Foundation

enum AppDestination: String, Equatable {
    case sort
}

/// Keeps an external route alive while authentication or the app lock is on
/// screen. RootTabView consumes it only once the tabs actually exist.
@MainActor
final class AppNavigation: ObservableObject {
    @Published var destination: AppDestination?

    func open(userInfo: [AnyHashable: Any]) {
        destination = NotificationRoute.destination(for: userInfo)
    }

    func open(url: URL) {
        destination = URLRoute.destination(for: url)
    }

    func consume(_ destination: AppDestination) {
        guard self.destination == destination else { return }
        self.destination = nil
    }
}

enum NotificationRoute {
    static func destination(for userInfo: [AnyHashable: Any]) -> AppDestination? {
        guard let rawValue = userInfo[DailyReminder.routeKey] as? String else { return nil }
        return AppDestination(rawValue: rawValue)
    }
}

enum URLRoute {
    static func destination(for url: URL) -> AppDestination? {
        guard url.scheme == "cashleak" else { return nil }
        return AppDestination(rawValue: url.host ?? "")
    }
}
