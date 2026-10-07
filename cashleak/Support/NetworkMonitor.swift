import Combine
import Foundation
import Network

/// Whether the phone has a connection, so Overview doesn't say "up to date"
/// when it can't know (D-037). Apple's `NWPathMonitor` — no permission, no
/// package, nothing sent anywhere.
@MainActor
final class NetworkMonitor: ObservableObject {

    static let shared = NetworkMonitor()

    @Published private(set) var isOffline = false

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status != .satisfied
            Task { @MainActor in
                self?.isOffline = offline
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.karasandlabs.cashleak.network"))
    }
}
