import SwiftUI

struct OperationsLogViewer: View {
    let session: OperationsSession
    var query: OperationsLogQuery
    @Environment(\.scenePhase) private var scenePhase
    @State private var entries: [OperationsLogEntry] = []
    @State private var search = ""
    @State private var level = "All levels"
    @State private var source = "All sources"
    @State private var follow = true
    @State private var failure: String?
    @State private var loading = false
    @State private var refreshID = UUID()

    private var filtered: [OperationsLogEntry] {
        entries.filter {
            (level == "All levels" || $0.level == level) && (source == "All sources" || $0.source == source)
                && (search.isEmpty || "\($0.message) \($0.source)".localizedCaseInsensitiveContains(search))
        }
    }
    private var exported: String {
        filtered.map { "\($0.time.formatted()) [\($0.level)] \($0.source): \($0.message)" }.joined(separator: "\n")
    }
    private struct PollKey: Hashable {
        let query: OperationsLogQuery
        let follow: Bool
        let active: Bool
        let agentID: UUID?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search log messages", text: $search).textFieldStyle(.roundedBorder)
            HStack {
                Picker("Level", selection: $level) {
                    ForEach(["All levels", "Info", "Warning", "Error", "Debug"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
                Picker("Source", selection: $source) {
                    Text("All sources").tag("All sources")
                    ForEach(Array(Set(entries.map(\.source))).sorted(), id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
                Spacer()
                ShareLink(item: exported) { Image(systemName: "square.and.arrow.up") }
                    .disabled(filtered.isEmpty).accessibilityLabel("Export visible logs")
            }
            HStack {
                Toggle("Follow", isOn: $follow).font(.caption).fixedSize()
                Spacer()
                Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(loading).accessibilityLabel("Refresh logs")
            }
            Text(session.isDemo ? "Demo log history · \(filtered.count) lines" : "Latest \(query.limit) lines · \(follow ? "Polling" : "Paused")")
                .font(.caption2).foregroundStyle(.secondary)
            if let failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(filtered) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(entry.time.formatted(date: .omitted, time: .standard)) · \(entry.level) · \(entry.source)")
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(entry.message).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading).id(entry.id)
                        }
                        if filtered.isEmpty && !loading { Text("No matching log entries.").foregroundStyle(.secondary) }
                    }.padding(.vertical, 8)
                }
                .onChange(of: filtered.last?.id) { _, last in
                    if follow, let last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
        .onChange(of: query) { _, _ in entries = []; source = "All sources"; failure = nil }
        .task(id: PollKey(query: query, follow: follow, active: scenePhase == .active, agentID: session.agent?.id)) {
            guard scenePhase == .active else { return }
            repeat {
                await reload()
                if !follow { break }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            } while !Task.isCancelled
        }
    }

    private func reload() async {
        let token = UUID()
        refreshID = token
        loading = true
        defer { if refreshID == token { loading = false } }
        do {
            let lines = try await session.logs(query)
            guard !Task.isCancelled, refreshID == token else { return }
            entries = lines
            failure = nil
        } catch {
            if !Task.isCancelled && refreshID == token { failure = error.localizedDescription }
        }
    }
}

struct OperationsProcessDetail: View {
    let process: OperationsProcess
    let session: OperationsSession
    @Environment(\.dismiss) private var dismiss
    @State private var pending: OperationsAction?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LabeledContent("PID", value: "\(process.id)")
                    LabeledContent("User", value: process.user)
                    LabeledContent("State", value: process.state)
                    LabeledContent("CPU", value: "\(process.cpuPercent.formatted())%")
                    LabeledContent("Memory", value: "\((process.memoryBytes / 1_048_576).formatted()) MiB")
                    LabeledContent("Threads", value: "\(process.threads)")
                    LabeledContent("Started", value: process.startedAt.formatted())
                    if let service = process.managedService { LabeledContent("Managed service", value: service) }
                    Text(process.command).font(.system(.caption, design: .monospaced)).textSelection(.enabled).operationsCard()
                    Button("Restart process", systemImage: "arrow.clockwise") {
                        pending = OperationsAction(kind: .restartProcess, target: "\(process.name) (PID \(process.id))",
                                                   processID: process.id, processStartedAt: process.startedAt)
                    }
                    .buttonStyle(.glass)
                    .disabled(process.id == 1 || process.restartSupported != true || session.performing || !allows(.restartProcess))
                    if process.restartSupported != true {
                        Text("Restart requires a service or process managed by the agent.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Terminate process", systemImage: "stop.circle") {
                        pending = OperationsAction(kind: .terminateProcess, target: "\(process.name) (PID \(process.id))",
                                                   processID: process.id, processStartedAt: process.startedAt)
                    }
                    .buttonStyle(.glass)
                    .disabled(process.id == 1 || session.performing || !allows(.terminateProcess))
                }.padding(20)
            }
            .navigationTitle(process.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .sheet(item: $pending) { OperationsConfirmation(action: $0, session: session) }
        .onChange(of: session.snapshot?.processes.contains(where: { $0.id == process.id && $0.startedAt == process.startedAt })) { _, present in
            if present == false { dismiss() }
        }
        .preferredColorScheme(.dark).tint(Color(white: 0.75))
    }
    private func allows(_ kind: OperationsAction.Kind) -> Bool { session.snapshot?.allowedActions.contains(kind) == true }
}

struct OperationsResourceDetail: View {
    let initial: OperationsResource
    let session: OperationsSession
    @Environment(\.dismiss) private var dismiss
    @State private var tab = "Details"
    @State private var container: String
    @State private var previous = false
    @State private var replicas: Int
    @State private var manifest: String
    @State private var baseVersion: String
    @State private var pending: OperationsAction?

    init(initial: OperationsResource, session: OperationsSession) {
        self.initial = initial; self.session = session
        _container = State(initialValue: initial.containers.first ?? "")
        _replicas = State(initialValue: initial.desired ?? 1)
        _manifest = State(initialValue: initial.manifest)
        _baseVersion = State(initialValue: initial.version)
    }
    private var resource: OperationsResource {
        session.snapshot?.resources.first(where: { $0.id == initial.id }) ?? initial
    }
    private var tabs: [String] { resource.kind == .pods ? ["Details", "Logs", "Manifest", "Shell"] : ["Details", "Manifest"] }

    var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text((session.agent?.title ?? "Agent disconnected") + (session.isDemo ? " · Demo session" : ""))
                    .font(.caption2).foregroundStyle(.secondary)
                Text("\(resource.kind.rawValue) · \(resource.namespace ?? "Cluster scope") · \(resource.status)")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Inspector", selection: $tab) {
                    ForEach(tabs, id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented)
                if tab == "Logs" || tab == "Shell" {
                    Picker("Container", selection: $container) {
                        ForEach(resource.containers, id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.menu)
                }
                Group {
                    if tab == "Logs" {
                        Toggle("Previous terminated container", isOn: $previous).font(.caption)
                        OperationsLogViewer(session: session, query: .init(source: "pod", resourceID: resource.id, container: container, previous: previous))
                    } else if tab == "Shell" {
                        OperationsConsole(session: session, resource: resource, container: container)
                    } else if tab == "Manifest" {
                        manifestEditor
                    } else {
                        details
                    }
                }.frame(maxHeight: .infinity, alignment: .top)
            }.padding(.vertical, 12)
            .navigationTitle(resource.name).navigationBarTitleDisplayMode(.inline)
        .sheet(item: $pending) { OperationsConfirmation(action: $0, session: session) }
        .onChange(of: session.snapshot?.resources.contains(where: { $0.id == initial.id })) { _, present in
            if present == false { dismiss() }
        }
        .preferredColorScheme(.dark).tint(Color(white: 0.75))
    }

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("UID", value: resource.id)
                if let node = resource.node { LabeledContent("Node", value: node) }
                if let ready = resource.ready, let desired = resource.desired { LabeledContent("Ready", value: "\(ready) / \(desired)") }
                ForEach(resource.details.keys.sorted(), id: \.self) { key in
                    LabeledContent(key, value: resource.details[key] ?? "")
                }
                if resource.kind.supportsRestart { actionButton(.restartWorkload) }
                if resource.kind.supportsScale {
                    Stepper("Replicas: \(replicas)", value: $replicas, in: 0...1_000)
                    actionButton(.scaleWorkload)
                }
                if resource.kind == .nodes {
                    actionButton(.cordonNode); actionButton(.uncordonNode); actionButton(.drainNode)
                }
                if ![.nodes, .namespaces, .events, .secrets].contains(resource.kind) { actionButton(.deleteResource) }
                let related = session.snapshot?.resources.filter {
                    $0.kind == .events && $0.relatedIDs.contains(resource.id)
                } ?? []
                let linked = session.snapshot?.resources.filter { resource.relatedIDs.contains($0.id) } ?? []
                if !linked.isEmpty {
                    Text("Related resources").font(.headline)
                    ForEach(linked) { item in
                        NavigationLink("\(item.kind.rawValue)/\(item.name)", value: item)
                    }
                }
                if !related.isEmpty {
                    Text("Related events").font(.headline)
                    ForEach(related) { event in Text(event.details["Message"] ?? event.status).font(.caption).operationsCard() }
                }
            }
        }
    }

    private var manifestEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            if resource.kind == .secrets {
                Text("Secret values are not exposed in this inspector.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Name", value: resource.name)
                LabeledContent("Namespace", value: resource.namespace ?? "—")
                LabeledContent("UID", value: resource.id)
            } else {
                TextEditor(text: $manifest).font(.system(.caption, design: .monospaced))
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                if resource.version != baseVersion {
                    Text("The resource changed. Reload its manifest before applying edits.").font(.caption)
                    Button("Reload manifest") { manifest = resource.manifest; baseVersion = resource.version }
                }
                Button("Review and apply manifest", systemImage: "checkmark.circle") {
                    var action = request(.applyManifest)
                    action.manifest = manifest; action.expectedVersion = baseVersion
                    pending = action
                }
                .buttonStyle(.glass)
                .disabled(resource.version != baseVersion || manifest == resource.manifest || manifest.isEmpty || session.performing || !allows(.applyManifest) || [.events, .namespaces].contains(resource.kind))
            }
        }
    }
    private func allows(_ kind: OperationsAction.Kind) -> Bool { session.snapshot?.allowedActions.contains(kind) == true }
    private func request(_ kind: OperationsAction.Kind) -> OperationsAction {
        OperationsAction(kind: kind, target: "\(resource.kind.rawValue)/\(resource.name)", namespace: resource.namespace,
                         resourceID: resource.id, expectedVersion: resource.version, replicas: kind == .scaleWorkload ? replicas : nil)
    }
    private func actionButton(_ kind: OperationsAction.Kind) -> some View {
        Button(kind.title) { pending = request(kind) }.buttonStyle(.glass)
            .disabled(session.performing || !allows(kind))
    }
}

struct OperationsConsole: View {
    let session: OperationsSession
    var resource: OperationsResource? = nil
    var container: String? = nil
    @State private var command = ""
    @State private var pending: OperationsAction?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(resource == nil ? "Agent command console" : "Container command console").font(.headline)
            Text(session.isDemo ? "Commands are simulated in this demo. Interactive terminals require a streaming agent API." : "One-shot command execution. Interactive terminals require a streaming API.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $command).font(.system(.body, design: .monospaced))
                .frame(minHeight: 80, maxHeight: 140).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityLabel("Command to run")
            Button("Review command", systemImage: "play") {
                pending = OperationsAction(kind: .runCommand, target: resource?.name ?? session.agent?.title ?? "",
                    namespace: resource?.namespace, resourceID: resource?.id, expectedVersion: resource?.version,
                    command: command, container: container)
            }
            .buttonStyle(.glass)
            .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || command.contains("\0") || session.performing || session.snapshot?.allowedActions.contains(.runCommand) != true)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(session.activity.filter { $0.summary.hasPrefix(OperationsAction.Kind.runCommand.title) }) { receipt in
                        Text(receipt.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled).operationsCard()
                    }
                }
            }
        }.sheet(item: $pending) { OperationsConfirmation(action: $0, session: session) }
    }
}

struct OperationsConfirmation: View {
    let action: OperationsAction
    let session: OperationsSession
    @Environment(\.dismiss) private var dismiss
    @State private var submitting = false
    @State private var outcome: String?
    @State private var submitted = false
    @State private var agentID: UUID?
    init(action: OperationsAction, session: OperationsSession) {
        self.action = action; self.session = session; _agentID = State(initialValue: session.agent?.id)
    }
    private var impact: String {
        switch action.kind {
        case .terminateProcess: return "Request graceful termination of this exact process. Its PID and start time must still match."
        case .restartProcess: return "Restart this process through its service manager or agent supervisor. Its PID and start time must still match. The replacement has a new process identity and may briefly interrupt service."
        case .restartWorkload: return "Start a new rollout. Pods may be replaced and service availability may be affected."
        case .scaleWorkload: return "Change desired replicas to \(action.replicas ?? 0). Scaling to zero stops this workload."
        case .deleteResource: return "Delete this resource. Controllers may recreate Pods; deleting storage claims can affect retained data."
        case .cordonNode: return "Mark the node unschedulable for new Pods."
        case .uncordonNode: return "Allow Pods to be scheduled on this node."
        case .drainNode: return "Request eviction of eligible Pods, respecting disruption budgets. Workloads may move to other nodes."
        case .applyManifest: return "Submit the edited manifest against the resource version you reviewed."
        case .runCommand: return "Execute the exact command below on the selected agent or container."
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(session.agent?.title ?? "Agent disconnected").font(.headline)
                    Text(session.agent?.endpoint ?? "").font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Target", value: action.target)
                    if let namespace = action.namespace { LabeledContent("Namespace", value: namespace) }
                    if let container = action.container { LabeledContent("Container", value: container) }
                    Text(impact).font(.subheadline)
                    if session.isDemo { Text("Demo only: this changes the in-memory sample and does not affect a real server or cluster.").font(.caption).foregroundStyle(.secondary) }
                    if let payload = action.manifest ?? action.command {
                        Text(payload).font(.system(.caption, design: .monospaced)).textSelection(.enabled).operationsCard()
                    }
                    if action.kind == .applyManifest,
                       let previous = session.snapshot?.resources.first(where: { $0.id == action.resourceID })?.manifest {
                        Text("Current manifest").font(.caption.weight(.medium))
                        Text(previous).font(.system(.caption, design: .monospaced)).textSelection(.enabled).operationsCard()
                    }
                    if submitting { ProgressView("Submitting operation…") }
                    if let outcome { Text(outcome).font(.subheadline).textSelection(.enabled) }
                    Button(session.isDemo ? "Simulate \(action.kind.title.lowercased())" : action.kind.title) {
                        guard let agentID else { return }
                        submitting = true
                        Task {
                            await session.perform(action, expectedAgentID: agentID)
                            submitting = false
                            submitted = true
                            if let error = session.error {
                                outcome = error
                                session.error = nil
                            } else { dismiss() }
                        }
                    }
                    .buttonStyle(.glass)
                    .disabled(submitting || submitted || session.performing || session.agent?.id != agentID || agentID == nil)
                }.padding(24)
            }
            .navigationTitle(action.kind.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(submitted ? "Close" : "Cancel") { dismiss() }.disabled(submitting) } }
        }
        .interactiveDismissDisabled(submitting)
        .preferredColorScheme(.dark).tint(Color(white: 0.75))
    }
}
