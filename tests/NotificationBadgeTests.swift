import Foundation

// Run with: swiftc test/InboxNotification.swift tests/NotificationBadgeTests.swift -o /tmp/notification-badge-tests
@main
struct NotificationBadgeTests {
    static func main() throws {
        let first = InboxNotification(id: "first", title: "First", message: "", created: Date(),
                                      urgency: .info, initiallyRead: false)
        let second = InboxNotification(id: "second", title: "Second", message: "", created: Date(),
                                       urgency: .high, initiallyRead: true)
        let third = InboxNotification(id: "third", title: "Third", message: "", created: Date(),
                                      urgency: .critical, initiallyRead: false)
        let inbox = [first, second, third]

        func count(_ items: [InboxNotification] = inbox, read: Set<String> = [],
                   unread: Set<String> = [], deleted: Set<String> = [], archived: Set<String> = []) -> Int {
            InboxNotification.unreadCount(in: items, readIDs: read, unreadIDs: unread,
                                          deletedIDs: deleted, archivedIDs: archived)
        }

        func expect(_ actual: Int, _ expected: Int, _ scenario: String) {
            precondition(actual == expected, "\(scenario): expected \(expected), got \(actual)")
        }

        expect(count(), 2, "Only unread inbox items count")
        expect(count(read: ["first"]), 1, "Opening a notification reduces the count")
        expect(count(read: ["first"], unread: ["first"]), 2, "Mark unread overrides a saved read flag")
        expect(count(unread: ["second"]), 3, "An initially read notification can be marked unread")
        expect(count(archived: ["first"]), 1, "Archiving removes an unread item from the badge")
        expect(count(deleted: ["third"]), 1, "Deleting removes an unread item from the badge")
        expect(count(unread: ["first"], archived: ["first"]), 1, "Unread archive items stay excluded")
        expect(count(unread: ["third"], deleted: ["third"]), 1, "Unread deleted items stay excluded")
        expect(count(read: ["first", "third"]), 0, "Read all clears both badges")
        expect(count([]), 0, "An empty inbox clears both badges")
        expect(count(InboxNotification.samples), 7, "Initial sample count matches the inbox")

        let created = InboxNotification(id: "created", title: "Created", message: "", created: Date(),
                                        urgency: .low, initiallyRead: false)
        let persisted = try JSONDecoder().decode([InboxNotification].self,
                                                from: JSONEncoder().encode([created]))
        expect(count(inbox + persisted), 3, "A saved new notification increases the count")
        expect(count(inbox, read: ["old-id"], unread: ["removed-id"]), 2, "Stale saved flags don't add notifications")
        print("Notification badge tests passed (13 scenarios).")
    }
}
