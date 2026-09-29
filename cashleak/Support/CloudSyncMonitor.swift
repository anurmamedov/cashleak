import Combine
import CoreData
import Foundation

/// Whether iCloud is still delivering data, so Overview can say so.
///
/// The problem this answers: on a fresh install — a new TestFlight build, a
/// second device — the store fills from iCloud over seconds to minutes, on a
/// schedule iOS controls. Until then Overview shows $0 or a partial month, and
/// a finance app showing the wrong number with no explanation reads as lost
/// data. Nothing in the app can make that sync faster. It can stop the screen
/// from lying about it.
///
/// SwiftData's CloudKit mirroring runs on `NSPersistentCloudKitContainer`, which
/// posts `eventChangedNotification` for setup, import and export. Observing it
/// from SwiftData is not documented but is widely relied on. If it never fires,
/// this stays silent — `isImporting` false and `lastImportFinished` nil — and
/// Overview shows no sync line at all rather than a false "up to date".
@MainActor
final class CloudSyncMonitor: ObservableObject {

    static let shared = CloudSyncMonitor()

    /// An import (or the initial setup) is in progress right now.
    @Published private(set) var isImporting = false

    /// When the most recent import finished, if one has been seen this launch.
    @Published private(set) var lastImportFinished: Date?

    /// The most recent import reported failure.
    @Published private(set) var lastImportFailed = false

    private var inFlight: Set<UUID> = []
    private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else { return }

            let identifier = event.identifier
            let isImport = event.type == .import || event.type == .setup
            let finished = event.endDate
            let succeeded = event.succeeded

            MainActor.assumeIsolated {
                self?.record(
                    identifier: identifier,
                    isImport: isImport,
                    finished: finished,
                    succeeded: succeeded
                )
            }
        }
    }

    /// Exports are ignored: sending your own changes up doesn't change what
    /// this device shows.
    func record(identifier: UUID, isImport: Bool, finished: Date?, succeeded: Bool) {
        guard isImport else { return }

        if let finished {
            inFlight.remove(identifier)
            lastImportFinished = finished
            lastImportFailed = !succeeded
        } else {
            inFlight.insert(identifier)
        }
        isImporting = !inFlight.isEmpty
    }
}
