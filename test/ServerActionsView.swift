import SwiftUI

struct ServerAction: Identifiable, Codable, Hashable {
    var id = UUID()
    var serverID: UUID
    var title = ""
    var command = ""
    var symbol = "terminal"
}

// The HTTP/HTTPS adapter can supply this closure once the server API is defined.
struct ActionExecutionResult {
    let output: String
    let exitCode: Int
}

typealias ServerActionExecutor = (ServerProfile, ServerAction) async throws -> ActionExecutionResult

struct ServerActionsView: View {
    let titleOffset: CGFloat
    var dividerTrailingExtension: CGFloat = 0
    var execute: ServerActionExecutor? = nil
    @AppStorage("serverProfiles") private var savedProfiles = "[]"
    @AppStorage("serverActions") private var savedActions = "[]"
    @AppStorage("actionsGroupBy") private var grouping = "Server"
    @State private var editor: ServerAction?
    @State private var execution: ServerAction?
    @State private var pendingDeletion: ServerAction?
    @State private var storageError: String?

    private var servers: [ServerProfile] {
        (try? JSONDecoder().decode([ServerProfile].self, from: Data(savedProfiles.utf8))) ?? []
    }

    private var actions: [ServerAction] {
        (try? JSONDecoder().decode([ServerAction].self, from: Data(savedActions.utf8))) ?? []
    }

    private var visibleActions: [ServerAction] {
        actions.filter { action in servers.contains { $0.id == action.serverID } }
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)]

    private var headerActions: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Group by", selection: $grouping) {
                    ForEach(["None", "Server"], id: \.self) { Text($0).tag($0) }
                }
            } label: {
                Label("Group", systemImage: "square.grid.2x2")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.caption)
            }
            .buttonStyle(.glass)
            .controlSize(.small)

            Button {
                if let server = servers.first {
                    editor = ServerAction(serverID: server.id)
                }
            } label: {
                Label("Create action", systemImage: "plus")
            }
            .labelStyle(.iconOnly)
            .font(.system(size: 14))
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(servers.isEmpty)
        }
        .foregroundStyle(Color(white: 0.65))
        .offset(x: dividerTrailingExtension)
    }

    private func persist(_ updated: [ServerAction]) {
        do {
            let data = try JSONEncoder().encode(updated)
            savedActions = String(decoding: data, as: UTF8.self)
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func save(_ action: ServerAction) {
        guard servers.contains(where: { $0.id == action.serverID }) else {
            storageError = "This server was removed. Choose another server for the action."
            return
        }
        var updated = actions
        if let index = updated.firstIndex(where: { $0.id == action.id }) {
            updated[index] = action
        } else {
            updated.append(action)
        }
        persist(updated)
    }

    var body: some View {
        VStack(spacing: 6) {
            NodavexPageHeader(
                pageTitle: "Actions",
                titleOffset: titleOffset,
                dividerTrailingExtension: dividerTrailingExtension,
                actions: AnyView(headerActions)
            )

            if servers.isEmpty {
                ContentUnavailableView(
                    "No servers added",
                    systemImage: "server.rack",
                    description: Text("Add a server in Settings to create commands for it.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if grouping == "Server" {
                            ForEach(servers) { server in
                                serverSection(server)
                            }
                        } else if visibleActions.isEmpty {
                            ContentUnavailableView(
                                "No actions yet",
                                systemImage: "bolt",
                                description: Text("Use + to create a command for a server.")
                            )
                        } else {
                            actionGrid(visibleActions, showServer: true)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(.container, edges: [.leading, .trailing])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: [.leading, .trailing])
        .tint(Color(white: 0.75))
        .sheet(item: $editor) { action in
            ServerActionEditor(
                action: action,
                servers: servers,
                isNew: !actions.contains(where: { $0.id == action.id }),
                save: save
            )
        }
        .sheet(item: $execution) { action in
            ServerActionRunView(action: action, execute: execute)
        }
        .alert("Delete action?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                if let action = pendingDeletion {
                    persist(actions.filter { $0.id != action.id })
                }
                pendingDeletion = nil
            }
        } message: {
            Text("Remove \(pendingDeletion?.title ?? "this action") from this server?")
        }
        .alert("Could not save action", isPresented: Binding(
            get: { storageError != nil },
            set: { if !$0 { storageError = nil } }
        )) {
            Button("OK") { storageError = nil }
        } message: {
            Text(storageError ?? "")
        }
    }

    private func serverSection(_ server: ServerProfile) -> some View {
        let serverActions = actions.filter { $0.serverID == server.id }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(server.title)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.55))
                if !(server.enabled ?? true) {
                    Text("Disabled").font(.caption2).foregroundStyle(Color(white: 0.45))
                }
                Spacer(minLength: 8)
                Button {
                    editor = ServerAction(serverID: server.id)
                } label: {
                    Label("Create action for \(server.title)", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            .foregroundStyle(Color(white: 0.8))

            if serverActions.isEmpty {
                Text("No actions yet. Add a command such as shutdown or python3 script.py.")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.45))
                    .padding(.vertical, 8)
            } else {
                actionGrid(serverActions, showServer: false)
            }
        }
    }

    private func actionGrid(_ entries: [ServerAction], showServer: Bool) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(entries) { action in
                if let server = servers.first(where: { $0.id == action.serverID }) {
                    actionCard(action, server: server, showServer: showServer)
                }
            }
        }
    }

    private func actionCard(_ action: ServerAction, server: ServerProfile, showServer: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            Button { execution = action } label: {
                VStack(spacing: 10) {
                    Image(systemName: action.symbol)
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 30, weight: .light))
                        .frame(height: 40)
                    Text(action.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .frame(height: 40, alignment: .top)
                    Text(showServer ? server.title : action.command)
                        .font(showServer ? .caption : .system(.caption, design: .monospaced))
                        .foregroundStyle(Color(white: 0.5))
                        .lineLimit(2)
                        .frame(height: 32, alignment: .top)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.top, 28)
                .padding(.bottom, 16)
                .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Run \(action.title) on \(server.title)")
            .accessibilityHint("Review the server and command before execution.")

            Menu {
                Button { execution = action } label: {
                    Label("Run…", systemImage: "play")
                }
                Button { editor = action } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) { pendingDeletion = action } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline)
                    .foregroundStyle(Color(white: 0.55))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(action.title)")
        }
        .foregroundStyle(Color(white: 0.85))
    }
}

private struct ActionSymbol: Identifiable {
    let id: String
    let title: String

    static let choices: [ActionSymbol] = [
        .init(id: "terminal", title: "Terminal"),
        .init(id: "power", title: "Power"),
        .init(id: "arrow.clockwise", title: "Restart"),
        .init(id: "play", title: "Start"),
        .init(id: "stop", title: "Stop"),
        .init(id: "pause", title: "Pause"),
        .init(id: "bolt", title: "Run"),
        .init(id: "gearshape", title: "Settings"),
        .init(id: "wrench.and.screwdriver", title: "Maintenance"),
        .init(id: "hammer", title: "Build"),
        .init(id: "chevron.left.forwardslash.chevron.right", title: "Code"),
        .init(id: "doc.text", title: "Script"),
        .init(id: "folder", title: "Folder"),
        .init(id: "externaldrive", title: "Storage"),
        .init(id: "arrow.down.doc", title: "Download"),
        .init(id: "arrow.up.doc", title: "Upload"),
        .init(id: "arrow.triangle.2.circlepath", title: "Sync"),
        .init(id: "network", title: "Network"),
        .init(id: "server.rack", title: "Server"),
        .init(id: "cpu", title: "Process"),
        .init(id: "magnifyingglass", title: "Inspect"),
        .init(id: "checkmark.shield", title: "Security"),
        .init(id: "lock", title: "Lock"),
        .init(id: "trash", title: "Clean up")
    ]
}

private struct ServerActionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var action: ServerAction
    let servers: [ServerProfile]
    let isNew: Bool
    let save: (ServerAction) -> Void

    private var valid: Bool {
        !action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !action.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !action.command.contains("\0")
            && servers.contains(where: { $0.id == action.serverID })
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? "Create action" : "Edit action")
                .font(.title3.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            Form {
                Section("Action") {
                    if isNew {
                        Picker("Server", selection: $action.serverID) {
                            ForEach(servers) { server in
                                Text(server.title).tag(server.id)
                            }
                        }
                    } else {
                        LabeledContent("Server", value: servers.first(where: { $0.id == action.serverID })?.title ?? "Server removed")
                    }
                    TextField("Action name", text: $action.title)
                }
                Section {
                    TextEditor(text: $action.command)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 100)
                        .accessibilityLabel("Command")
                } header: {
                    Text("Command")
                } footer: {
                    Text("Enter the command to execute on this server, for example shutdown or python3 script.py. Use an absolute script path if needed.")
                }
                Section("Icon · Apple SF Symbols") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 12) {
                        ForEach(ActionSymbol.choices) { symbol in
                            Button { action.symbol = symbol.id } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: symbol.id)
                                        .symbolRenderingMode(.monochrome)
                                        .font(.title3)
                                        .frame(height: 26)
                                    Text(symbol.title)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(action.symbol == symbol.id ? Color(white: 0.25) : Color(white: 0.1), in: RoundedRectangle(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(action.symbol == symbol.id ? Color(white: 0.75) : .clear, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol.title)
                            .accessibilityAddTraits(action.symbol == symbol.id ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .scrollContentBackground(.hidden)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(isNew ? "Create" : "Save") {
                    action.title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Preserve shell whitespace and quoting exactly as entered.
                    save(action)
                    dismiss()
                }
                .disabled(!valid)
            }
            .buttonStyle(.glass)
            .padding(24)
        }
        .background(Color(white: 0.09))
        .presentationBackground(Color(white: 0.09))
        .preferredColorScheme(.dark)
        .tint(Color(white: 0.75))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct ServerActionRunView: View {
    @Environment(\.dismiss) private var dismiss
    let action: ServerAction
    let execute: ServerActionExecutor?
    @AppStorage("serverProfiles") private var savedProfiles = "[]"
    @State private var running = false
    @State private var result: ActionExecutionResult?
    @State private var failure: String?

    private var server: ServerProfile? {
        let profiles = (try? JSONDecoder().decode([ServerProfile].self, from: Data(savedProfiles.utf8))) ?? []
        return profiles.first { $0.id == action.serverID }
    }

    private var serverEnabled: Bool {
        server.map { $0.enabled ?? true } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label(action.title, systemImage: action.symbol)
                .symbolRenderingMode(.monochrome)
                .font(.title3.weight(.medium))
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(server?.title ?? "Server removed").font(.headline)
                        Text(server?.endpoint ?? "This action's server is no longer available.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(action.command)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 12))
                    if execute == nil {
                        Text("Execution unavailable. HTTP/HTTPS command execution has not been connected yet. Your action is saved and can be edited.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else if !serverEnabled {
                        Text("Enable this server in Settings before running an action.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("This command will execute on the server shown above.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if running {
                        ProgressView("Executing command…")
                    }
                    if let result {
                        Text(result.exitCode == 0 ? "Completed · Exit code 0" : "Failed · Exit code \(result.exitCode)")
                            .font(.subheadline.weight(.medium))
                        Text(result.output.isEmpty ? "No output returned." : result.output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    if let failure {
                        Text("Execution could not be confirmed: \(failure)")
                            .font(.subheadline)
                        Text("Check the server before trying again; the command may have started.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Close") { dismiss() }.disabled(running)
                Spacer()
                Button {
                    guard let execute, let server, server.enabled ?? true else { return }
                    running = true
                    result = nil
                    failure = nil
                    Task {
                        do { result = try await execute(server, action) }
                        catch { failure = error.localizedDescription }
                        running = false
                    }
                } label: {
                    Label("Run command", systemImage: "play")
                }
                .disabled(execute == nil || !serverEnabled || running || result != nil || failure != nil)
            }
            .buttonStyle(.glass)
        }
        .padding(24)
        .background(Color(white: 0.09))
        .presentationBackground(Color(white: 0.09))
        .preferredColorScheme(.dark)
        .tint(Color(white: 0.75))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(running)
    }
}
