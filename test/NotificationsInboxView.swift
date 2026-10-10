import SwiftUI

private struct UrgencyIndicator: View {
    @AppStorage("metricColoursEnabled") private var metricColoursEnabled = false
    let urgency: NotificationUrgency

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                ForEach(0..<urgency.circleCount, id: \.self) { _ in
                    Circle()
                        .fill(metricColoursEnabled ? MetricPalette.urgency(urgency.rawValue) : Color(white: 0.6))
                        .frame(width: 5, height: 5)
                }
            }
            Text(urgency.rawValue)
                .font(.caption2)
                .foregroundStyle(Color(white: 0.55))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(urgency.rawValue)
    }
}

struct NotificationsInboxView: View {
    let isPortrait: Bool
    let hasSideInset: Bool
    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge
    private var usesSideToolbar: Bool { toolbarVerticalEdge != nil || hasSideInset || !isPortrait }
    let titleOffset: CGFloat
    @AppStorage("serverProfiles") private var savedProfiles = "[]"
    @AppStorage("notificationsGroupBy") private var grouping = "None"
    @AppStorage("notificationsOrderBy") private var ordering = "Date created"
    @AppStorage("readDemoNotifications") private var savedReadIDs = ""
    @AppStorage("unreadNotifications") private var savedUnreadIDs = ""
    @AppStorage("deletedDemoNotifications") private var savedDeletedIDs = ""
    @AppStorage("archivedNotifications") private var savedArchivedIDs = ""
    @AppStorage("createdNotifications") private var savedCreatedNotifications = "[]"
    @AppStorage("sampleNotificationsRestoreVersion") private var sampleRestoreVersion = 0
    @State private var confirmingDeleteAll = false
    @State private var confirmingArchiveAll = false
    @State private var refreshRevision = 0
    @State private var showingComposer = false
    @State private var showingArchive = false
    @State private var selectedNotification: InboxNotification?

    private var servers: [ServerProfile] {
        (try? JSONDecoder().decode([ServerProfile].self, from: Data(savedProfiles.utf8))) ?? []
    }

    private func serverName(_ notification: InboxNotification) -> String {
        servers.first(where: { $0.id == notification.serverID })?.title ?? "Unassigned"
    }

    private var notificationGroups: [(title: String, items: [InboxNotification])] {
        let sorted = notifications.sorted { lhs, rhs in
            switch ordering {
            case "Server":
                let a = serverName(lhs), b = serverName(rhs)
                if a != b { return a.localizedStandardCompare(b) == .orderedAscending }
            case "Criticality":
                if lhs.urgency.circleCount != rhs.urgency.circleCount {
                    return lhs.urgency.circleCount > rhs.urgency.circleCount
                }
            default: break
            }
            return lhs.created > rhs.created
        }
        guard grouping != "None" else { return [("", sorted)] }
        let grouped = Dictionary(grouping: sorted) { notification in
            grouping == "Server" ? serverName(notification) : notification.urgency.rawValue
        }
        let keys = grouped.keys.sorted { a, b in
            if grouping == "Criticality" {
                return (NotificationUrgency(rawValue: a)?.circleCount ?? 0) > (NotificationUrgency(rawValue: b)?.circleCount ?? 0)
            }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
        return keys.map { ($0, grouped[$0] ?? []) }
    }

    private var allNotifications: [InboxNotification] {
        _ = refreshRevision
        let created = (try? JSONDecoder().decode([InboxNotification].self, from: Data(savedCreatedNotifications.utf8))) ?? []
        return (created + InboxNotification.samples).sorted { $0.created > $1.created }
    }

    private var notifications: [InboxNotification] {
        let deleted = Set(savedDeletedIDs.split(separator: ",").map(String.init))
        let archived = Set(savedArchivedIDs.split(separator: ",").map(String.init))
        return allNotifications.filter { !deleted.contains($0.id) && archived.contains($0.id) == showingArchive }
    }

    private func readAll() {
        var ids = Set(savedReadIDs.split(separator: ",").map(String.init))
        ids.formUnion(notifications.map(\.id))
        let visibleIDs = Set(notifications.map(\.id))
        savedUnreadIDs = savedUnreadIDs.split(separator: ",")
            .filter { !visibleIDs.contains(String($0)) }.joined(separator: ",")
        savedReadIDs = ids.sorted().joined(separator: ",")
    }

    private func deleteAll() {
        var ids = Set(savedDeletedIDs.split(separator: ",").map(String.init))
        ids.formUnion(notifications.map(\.id))
        withAnimation { savedDeletedIDs = ids.sorted().joined(separator: ",") }
    }

    private func archiveAll() {
        var ids = Set(savedArchivedIDs.split(separator: ",").map(String.init))
        ids.formUnion(notifications.map(\.id))
        withAnimation { savedArchivedIDs = ids.sorted().joined(separator: ",") }
    }

    private func create(title: String, message: String, urgency: NotificationUrgency, serverID: UUID?) {
        var created = (try? JSONDecoder().decode([InboxNotification].self, from: Data(savedCreatedNotifications.utf8))) ?? []
        created.insert(InboxNotification(id: UUID().uuidString, title: title, message: message,
                                       created: Date(), urgency: urgency, initiallyRead: false, serverID: serverID), at: 0)
        if let data = try? JSONEncoder().encode(created), let json = String(data: data, encoding: .utf8) {
            savedCreatedNotifications = json
            showingArchive = false
        }
    }

    @MainActor
    private func refreshNotifications() async {
        // Local reloads are nearly instant. Keep the native refresh cycle active
        // while its pull-down animation opens and the refreshed rows settle.
        do {
            try await Task.sleep(for: .milliseconds(500))
            try Task.checkCancellation()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                refreshRevision += 1
            }
            try await Task.sleep(for: .milliseconds(250))
        } catch {
            // Cancellation lets the native refresh control end normally.
        }
    }

    private func delete(_ notification: InboxNotification) {
        var deleted = Set(savedDeletedIDs.split(separator: ",").map(String.init))
        deleted.insert(notification.id)
        withAnimation {
            savedDeletedIDs = deleted.sorted().joined(separator: ",")
        }
    }

    private func isRead(_ notification: InboxNotification) -> Bool {
        notification.isRead(
            readIDs: Set(savedReadIDs.split(separator: ",").map(String.init)),
            unreadIDs: Set(savedUnreadIDs.split(separator: ",").map(String.init))
        )
    }

    private func markRead(_ notification: InboxNotification) {
        guard !isRead(notification) else { return }
        var ids = Set(savedReadIDs.split(separator: ",").map(String.init))
        ids.insert(notification.id)
        savedUnreadIDs = savedUnreadIDs.split(separator: ",")
            .filter { $0 != Substring(notification.id) }.joined(separator: ",")
        withAnimation(.easeInOut(duration: 0.2)) {
            savedReadIDs = ids.sorted().joined(separator: ",")
        }
    }

    private func markUnread(_ notification: InboxNotification) {
        var unread = Set(savedUnreadIDs.split(separator: ",").map(String.init))
        unread.insert(notification.id)
        withAnimation(.easeInOut(duration: 0.2)) {
            savedUnreadIDs = unread.sorted().joined(separator: ",")
            savedReadIDs = savedReadIDs.split(separator: ",")
                .filter { $0 != Substring(notification.id) }.joined(separator: ",")
        }
    }

    private var headerTrailingContent: AnyView? {
        if let notification = selectedNotification {
            return AnyView(
                VStack(alignment: .trailing, spacing: 5) {
                    Text(notification.created, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        .font(.caption2)
                        .foregroundStyle(Color(white: 0.4))
                    UrgencyIndicator(urgency: notification.urgency)
                }
                .multilineTextAlignment(.trailing)
            )
        }
        if usesSideToolbar { return nil }
        return AnyView(
            HStack(spacing: 8) {
                Menu {
                    Picker("Group by", selection: $grouping) {
                        ForEach(["None", "Criticality", "Server"], id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    Label("Group", systemImage: "square.grid.2x2")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .font(.caption)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                Menu {
                    Picker("Order by", selection: $ordering) {
                        ForEach(["Server", "Criticality", "Date created"], id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .font(.caption)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                if !usesSideToolbar {
                    compactActions
                        .padding(.leading, 8)
                }
            }
            .foregroundStyle(Color(white: 0.65))
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            NodavexPageHeader(pageTitle: selectedNotification?.title ?? "Notifications", titleOffset: titleOffset,
                              actions: headerTrailingContent,
                              backAction: selectedNotification != nil ? {
                                  selectedNotification = nil
                              } : nil)
            NavigationStack {
            Group {
                if notifications.isEmpty {
                    GeometryReader { geometry in
                        ScrollView {
                            Text(showingArchive ? "Empty archive" : "Empty inbox")
                                .font(.subheadline.weight(.light))
                                .foregroundStyle(Color(white: 0.4))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: geometry.size.height)
                        }
                        .modifier(LeftNotificationScrollIndicator())
                        .refreshable { await refreshNotifications() }
                        .scrollBounceBehavior(.always)
                    }
                } else {
                    List {
                        ForEach(notificationGroups, id: \.title) { group in
                        Section {
                        ForEach(group.items) { notification in
                            Button {
                                selectedNotification = notification
                                markRead(notification)
                            } label: {
                                row(notification)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the full notification")
                            .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(notification)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)

                                Button {
                                    if isRead(notification) {
                                        markUnread(notification)
                                    } else {
                                        markRead(notification)
                                    }
                                } label: {
                                    Label(isRead(notification) ? "Mark unread" : "Mark read",
                                          systemImage: isRead(notification) ? "envelope.badge" : "envelope.open")
                                }
                                .tint(Color(white: 0.35))
                            }
                        }
                        } header: {
                            if !group.title.isEmpty {
                                Text(group.title)
                                    .font(.caption)
                                    .foregroundStyle(Color(white: 0.55))
                                    .textCase(nil)
                            }
                        }
                        }
                    }
                    .modifier(LeftNotificationScrollIndicator())
                    .listStyle(.plain)
                    .refreshable { await refreshNotifications() }
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, 0)
                }
            }
            .navigationDestination(item: $selectedNotification) { notification in
                NotificationDetailView(notification: notification)
            }
            .background(Color.black)
            // The outer TabView already reserves the sidebar's width. Only
            // remove the duplicate inset inside this nested navigation content.
            .ignoresSafeArea(.container, edges: [.top, .leading, .trailing])
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                if usesSideToolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Group", selection: $grouping) {
                            ForEach(["None", "Criticality", "Server"], id: \.self) { Text($0).tag($0) }
                        }
                    } label: { Label("Group", systemImage: "square.grid.2x2") }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $ordering) {
                            ForEach(["Server", "Criticality", "Date created"], id: \.self) { Text($0).tag($0) }
                        }
                    } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: readAll) {
                        Label("Read all", systemImage: "checkmark.circle")
                    }
                    .disabled(notifications.isEmpty)
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        confirmingDeleteAll = true
                    } label: {
                        Label("Delete all", systemImage: "trash")
                    }
                    .tint(.white)
                    .disabled(notifications.isEmpty)
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Archive all", systemImage: "archivebox") {
                            confirmingArchiveAll = true
                        }
                            .disabled(showingArchive || notifications.isEmpty)
                        Button(showingArchive ? "Show inbox" : "Show archive", systemImage: showingArchive ? "tray" : "archivebox") {
                            showingArchive.toggle()
                        }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingComposer = true
                    } label: {
                        Label("Create notification", systemImage: "square.and.pencil")
                    }
                }
                }
            }
            }
        }
        .alert("Delete all notifications?", isPresented: $confirmingDeleteAll) {
            Button("Delete All", role: .destructive) {
                deleteAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete all \(notifications.count) notifications in the current view.")
        }
        .alert("Archive all notifications?", isPresented: $confirmingArchiveAll) {
            Button("Archive All") {
                archiveAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Move all \(notifications.count) notifications from your inbox to the archive?")
        }
        .sheet(isPresented: $showingComposer) {
            NotificationComposer { title, message, urgency, serverID in
                create(title: title, message: message, urgency: urgency, serverID: serverID)
            }
        }
        .onAppear {
            if sampleRestoreVersion < 1 {
                savedDeletedIDs = savedDeletedIDs.split(separator: ",")
                    .filter { !$0.hasPrefix("demo-notification-") }.joined(separator: ",")
                savedArchivedIDs = savedArchivedIDs.split(separator: ",")
                    .filter { !$0.hasPrefix("demo-notification-") }.joined(separator: ",")
                savedReadIDs = savedReadIDs.split(separator: ",")
                    .filter { !$0.hasPrefix("demo-notification-") }.joined(separator: ",")
                sampleRestoreVersion = 1
            }
        }
        .tint(Color(white: 0.75))

    }

    private var compactActions: some View {
        HStack(spacing: 8) {
            Button(action: readAll) {
                Label("Read all", systemImage: "checkmark.circle")
            }
            .disabled(notifications.isEmpty)
            Button { confirmingDeleteAll = true } label: {
                Label("Delete all", systemImage: "trash")
            }
            .disabled(notifications.isEmpty)
            Menu {
                Button("Archive all", systemImage: "archivebox") { confirmingArchiveAll = true }
                    .disabled(showingArchive || notifications.isEmpty)
                Button(showingArchive ? "Show inbox" : "Show archive") { showingArchive.toggle() }
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
            Button { showingComposer = true } label: {
                Label("Create notification", systemImage: "square.and.pencil")
            }
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 14))
        .buttonStyle(.glass)
        .controlSize(.small)
        .tint(Color(white: 0.75))
    }

    private func row(_ notification: InboxNotification) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(isRead(notification) ? Color(white: 0.3) : .white)
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 4) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        title(notification)
                        Spacer(minLength: 8)
                        date(notification)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        title(notification)
                        date(notification)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                Text(notification.message)
                    .lineLimit(1)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.55))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                UrgencyIndicator(urgency: notification.urgency)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isRead(notification) ? "Read" : "Unread")
    }

    private func title(_ notification: InboxNotification) -> some View {
        Text(notification.title)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color(white: isRead(notification) ? 0.65 : 0.9))
            .multilineTextAlignment(.leading)
    }

    private func date(_ notification: InboxNotification) -> some View {
        Text(notification.created, format: .dateTime.day().month(.abbreviated).hour().minute())
            .font(.caption2)
            .foregroundStyle(Color(white: 0.4))
            .fixedSize()
    }
}

private struct NotificationDetailView: View {
    let notification: InboxNotification

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(notification.message)
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.75))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .modifier(LeftNotificationScrollIndicator())
        .background(Color.black)
        .ignoresSafeArea(.container, edges: [.leading, .trailing])
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

private struct NotificationComposer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var content = ""
    @State private var urgency: NotificationUrgency = .info
    @AppStorage("serverProfiles") private var savedProfiles = "[]"
    @State private var serverID: UUID?
    let submit: (String, String, NotificationUrgency, UUID?) -> Void

    private var servers: [ServerProfile] {
        (try? JSONDecoder().decode([ServerProfile].self, from: Data(savedProfiles.utf8))) ?? []
    }

    private var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanContent: String { content.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Create notification")
                .font(.title3.weight(.medium))

            VStack(alignment: .leading, spacing: 8) {
                Text("Title").font(.caption).foregroundStyle(.secondary)
                TextField("Notification title", text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            Picker("Server", selection: $serverID) {
                Text("Unassigned").tag(nil as UUID?)
                ForEach(servers) { server in
                    Text(server.title).tag(Optional(server.id))
                }
            }
            .pickerStyle(.menu)

            HStack {
                Text("Criticality")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Criticality", selection: $urgency) {
                    ForEach(NotificationUrgency.allCases, id: \.self) { level in
                        Text(String(repeating: "●", count: level.circleCount) + "   " + level.rawValue)
                            .tag(level)
                    }
                }
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Content").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $content)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Notification content")
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.glass)
                Spacer()
                Button("Submit") {
                    submit(cleanTitle, cleanContent, urgency, serverID)
                    dismiss()
                }
                .buttonStyle(.glass)
                .disabled(cleanTitle.isEmpty || cleanContent.isEmpty)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 8)
        .background(Color(white: 0.09))
        .preferredColorScheme(.dark)
        .tint(Color(white: 0.75))
        .presentationBackground(Color(white: 0.09))
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .statusBarHidden(true)
    }
}

// Use the same left-side, scrolling-only indicator for the inbox and details.
private struct LeftNotificationScrollIndicator: ViewModifier {
    @State private var metrics: [CGFloat] = [0, 0, 0]
    @State private var isScrolling = false

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: [CGFloat].self) { scroll in
                [scroll.contentOffset.y + scroll.contentInsets.top,
                 scroll.contentSize.height + scroll.contentInsets.top + scroll.contentInsets.bottom,
                 scroll.containerSize.height]
            } action: { _, newMetrics in
                metrics = newMetrics
            }
            .onScrollPhaseChange { _, phase in
                withAnimation(.easeOut(duration: phase == .idle ? 0.35 : 0.1)) {
                    isScrolling = phase != .idle
                }
            }
            .overlay(alignment: .leading) {
                GeometryReader { viewport in
                    let contentHeight = metrics[1]
                    let visibleHeight = metrics[2]
                    if contentHeight > visibleHeight, visibleHeight > 0 {
                        let trackHeight = max(0, viewport.size.height - 8)
                        let thumbHeight = min(trackHeight, max(28, trackHeight * visibleHeight / contentHeight))
                        let fraction = min(1, max(0, metrics[0] / (contentHeight - visibleHeight)))
                        Capsule()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 3, height: thumbHeight)
                            .offset(x: -10, y: 4 + fraction * (trackHeight - thumbHeight))
                    }
                }
                .opacity(isScrolling ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}
