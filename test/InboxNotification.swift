import Foundation

enum NotificationUrgency: String, Hashable, Codable, CaseIterable {
    case info = "Info", low = "Low", medium = "Medium", high = "High", critical = "Critical"

    var circleCount: Int {
        switch self {
        case .info: return 1
        case .low: return 2
        case .medium: return 3
        case .high: return 4
        case .critical: return 5
        }
    }
}

struct InboxNotification: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let message: String
    let created: Date
    let urgency: NotificationUrgency
    let initiallyRead: Bool
    var serverID: UUID? = nil

    func isRead(readIDs: Set<String>, unreadIDs: Set<String>) -> Bool {
        if unreadIDs.contains(id) { return false }
        return initiallyRead || readIDs.contains(id)
    }

    static func unreadCount(in notifications: [InboxNotification], readIDs: Set<String>,
                            unreadIDs: Set<String>, deletedIDs: Set<String>, archivedIDs: Set<String>) -> Int {
        notifications.filter {
            !deletedIDs.contains($0.id) && !archivedIDs.contains($0.id)
                && !$0.isRead(readIDs: readIDs, unreadIDs: unreadIDs)
        }.count
    }

    static let samples: [InboxNotification] = {
        let calendar = Calendar(identifier: .gregorian)
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 18, minute: 30))!
        let entries: [(String, String, NotificationUrgency, Bool)] = [
            ("Database unavailable", "The production database is not responding to health checks.", .critical, false),
            ("Disk space running low", "Storage on web-02 has reached 92% capacity.", .high, false),
            ("Backup completed", "The nightly backup completed successfully for all selected hosts.", .info, false),
            ("Memory usage elevated", "Application memory usage has remained above 80% for 15 minutes.", .medium, false),
            ("Certificate expires soon", "The API certificate expires in 7 days. Schedule a renewal.", .high, false),
            ("Updates available", "Three servers have new security updates available.", .low, false),
            ("Network latency increased", "Average response time to the gateway has increased to 120 ms.", .medium, false),
            ("Service restarted", "The reverse proxy restarted successfully on edge-01.", .info, true),
            ("Host back online", "Monitoring has reconnected to worker-03.", .info, true),
            ("Backup verification failed", "The latest archive on backup-02 could not be verified.", .critical, true)
        ]
        return entries.enumerated().map { index, item in
            InboxNotification(id: "demo-notification-\(index)", title: item.0, message: item.1,
                              created: base.addingTimeInterval(-Double(index) * 3600),
                              urgency: item.2, initiallyRead: item.3)
        }
    }()
}

