import SwiftUI
import UserNotifications
import OSLog

// Both badges observe the same persisted inbox state, regardless of the selected tab.
struct NotificationBadgeState: DynamicProperty {
    @AppStorage("readDemoNotifications") private var readIDs = ""
    @AppStorage("unreadNotifications") private var unreadIDs = ""
    @AppStorage("deletedDemoNotifications") private var deletedIDs = ""
    @AppStorage("archivedNotifications") private var archivedIDs = ""
    @AppStorage("createdNotifications") private var createdNotifications = "[]"

    var unreadCount: Int {
        let created = (try? JSONDecoder().decode([InboxNotification].self,
                                               from: Data(createdNotifications.utf8))) ?? []
        return InboxNotification.unreadCount(
            in: created + InboxNotification.samples,
            readIDs: Set(readIDs.split(separator: ",").map(String.init)),
            unreadIDs: Set(unreadIDs.split(separator: ",").map(String.init)),
            deletedIDs: Set(deletedIDs.split(separator: ",").map(String.init)),
            archivedIDs: Set(archivedIDs.split(separator: ",").map(String.init))
        )
    }
}

struct NotificationIconBadgeModifier: ViewModifier {
    let count: Int
    let requestPermission: Bool
    @Environment(\.scenePhase) private var scenePhase
    @State private var synchronizer = NotificationBadgeSynchronizer()

    func body(content: Content) -> some View {
        content
            .onChange(of: count, initial: true) { _, _ in synchronize() }
            .onChange(of: requestPermission) { _, _ in synchronize() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { synchronize() }
            }
    }

    private func synchronize() {
        // Keep the final update alive when the user immediately returns to the Home Screen.
        Task { await synchronizer.update(count: count, requestPermission: requestPermission) }
    }
}

@MainActor
private final class NotificationBadgeSynchronizer {
    private var latestCount = 0
    private var mayRequestPermission = false
    private var updating = false
    private let logger = Logger(subsystem: "com.conorsokellpersonalteam.nodavex", category: "NotificationBadge")

    func update(count: Int, requestPermission: Bool) async {
        latestCount = count
        mayRequestPermission = mayRequestPermission || requestPermission
        guard !updating else { return }
        updating = true
        defer { updating = false }

        let center = UNUserNotificationCenter.current()
        do {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                guard mayRequestPermission else { return }
                guard try await center.requestAuthorization(options: [.badge]) else { return }
            } else if settings.badgeSetting != .enabled {
                return
            }

            // Serialize writes so a slow previous request cannot restore an outdated count.
            while true {
                let target = latestCount
                try await center.setBadgeCount(target)
                if latestCount == target { break }
            }
        } catch {
            logger.error("Could not update the app icon badge: \(error.localizedDescription, privacy: .public)")
        }
    }
}
