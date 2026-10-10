import SwiftUI
import Charts

struct OperationsView: View {
    let titleOffset: CGFloat
    var dividerTrailingExtension: CGFloat = 0
    var liveClient: (any AgentOperationsClient)? = nil
    @AppStorage("serverProfiles") private var savedProfiles = "[]"
    @State private var session = OperationsSession()
    @State private var area = OperationsArea.overview
    @State private var choosingAgent = false
    @State private var search = ""
    @State private var namespace = "All namespaces"
    @State private var kind = KubernetesResourceKind.pods
    @State private var processSort = "CPU"
    @State private var selectedProcess: OperationsProcess?
    @State private var resourcePath: [OperationsResource] = []

    private var agents: [ServerProfile] {
        (try? JSONDecoder().decode([ServerProfile].self, from: Data(savedProfiles.utf8))) ?? []
    }
    private var resources: [OperationsResource] {
        (session.snapshot?.resources ?? []).filter {
            $0.kind == kind && (namespace == "All namespaces" || $0.namespace == namespace || $0.namespace == nil)
                && (search.isEmpty || "\($0.name) \($0.status)".localizedCaseInsensitiveContains(search))
        }
    }
    private var processes: [OperationsProcess] {
        (session.snapshot?.processes ?? []).filter {
            search.isEmpty || "\($0.id) \($0.name) \($0.user) \($0.command)".localizedCaseInsensitiveContains(search)
        }.sorted {
            switch processSort {
            case "Memory": return $0.memoryBytes > $1.memoryBytes
            case "PID": return $0.id < $1.id
            default: return $0.cpuPercent > $1.cpuPercent
            }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            NodavexPageHeader(pageTitle: resourcePath.last?.name ?? "Operations", titleOffset: titleOffset,
                dividerTrailingExtension: dividerTrailingExtension, actions: AnyView(connectionMenu),
                backAction: resourcePath.isEmpty ? nil : { resourcePath.removeLast() })
            NavigationStack(path: $resourcePath) {
                Group {
                    if session.agent != nil {
                        workspace
                    } else {
                        VStack(spacing: 20) {
                            ContentUnavailableView("Connect to an agent", systemImage: "network",
                                description: Text("Investigate processes, logs, metrics, and Kubernetes resources. One agent is active at a time."))
                            Button("Choose agent") { choosingAgent = true }.buttonStyle(.glass)
                            Text("Open the Kubernetes demo agent to explore. Live connections require the Nodavex agent API adapter.")
                                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Spacer()
                        }
                    }
                }
                // LandingView already sizes this page beside the native tab sidebar.
                // Do not reserve its horizontal safe area again inside navigation.
                .ignoresSafeArea(.container, edges: [.leading, .trailing])
                .navigationDestination(for: OperationsResource.self) { resource in
                    OperationsResourceDetail(initial: resource, session: session)
                        .ignoresSafeArea(.container, edges: [.leading, .trailing])
                        .toolbar(.hidden, for: .navigationBar)
                }
                .toolbar(.hidden, for: .navigationBar)
                .toolbarBackground(.hidden, for: .navigationBar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(.container, edges: [.leading, .trailing])
        .tint(Color(white: 0.75))
        .sheet(isPresented: $choosingAgent) { agentChooser }
        .sheet(item: $selectedProcess) { process in
            OperationsProcessDetail(process: process, session: session)
        }
        .alert("Operations", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) {
            Button("OK") { session.error = nil }
        } message: { Text(session.error ?? "") }
        .onChange(of: savedProfiles) { _, _ in
            if let active = session.agent,
               !agents.contains(where: { $0.id == active.id && $0 == active && ($0.enabled ?? true) }) {
                session.disconnect()
                selectedProcess = nil
                resourcePath.removeAll()
            }
        }
        .onChange(of: session.agent?.id) { _, _ in
            area = .overview; search = ""; namespace = "All namespaces"
            selectedProcess = nil; resourcePath.removeAll()
        }
        .onChange(of: area) { _, _ in search = "" }
    }

    private var connectionMenu: some View {
        Menu {
            Button("Choose / switch agent", systemImage: "arrow.triangle.2.circlepath") { choosingAgent = true }
            if session.agent != nil {
                Button("Disconnect", systemImage: "link.badge.plus") { session.disconnect() }
            }
        } label: {
            Label(session.agent == nil ? "Connect" : "Agent", systemImage: "network")
                .font(.caption)
        }
        .buttonStyle(.glass).controlSize(.small)
        .disabled(session.performing)
    }

    private var agentChooser: some View {
        NavigationStack {
            List {
                Section("One active agent at a time") {
                    ForEach(agents) { agent in
                        let demo = agent.id == ServerProfile.kubernetesSample.id && agent.hostname == ServerProfile.kubernetesSample.hostname
                        Button {
                            choosingAgent = false
                            Task { await session.connect(agent, liveClient: liveClient) }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(agent.title)
                                Text(agent.endpoint).font(.caption).foregroundStyle(.secondary)
                                Text(!(agent.enabled ?? true) ? "Disabled" : demo ? "Open demo session" : liveClient == nil ? "Live API not configured" : "Connect")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(!(agent.enabled ?? true) || (!demo && liveClient == nil) || session.performing)
                    }
                }
                if agents.isEmpty { Text("Add a Nodavex agent in Settings.") }
            }
            .navigationTitle("Choose agent").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { choosingAgent = false } } }
        }
        .preferredColorScheme(.dark).tint(Color(white: 0.75))
    }

    private var workspace: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.agent?.title ?? "").font(.subheadline.weight(.medium))
                    Text(session.isDemo ? "Demo session · All changes are simulated" : session.agent?.endpoint ?? "")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await session.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(session.loading || session.performing)
                    .accessibilityLabel("Refresh operations")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(OperationsArea.allCases.filter { $0 != .kubernetes || session.agent?.kubernetes == true }) { item in
                        Button { area = item } label: {
                            Label(item.rawValue, systemImage: item.symbol)
                                .font(.caption).padding(.horizontal, 12).padding(.vertical, 9)
                                .background(area == item ? Color(white: 0.25) : Color(white: 0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(area == item ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            if session.loading && session.snapshot == nil { ProgressView("Loading agent…") }
            GeometryReader { viewport in
            Group {
                switch area {
                case .overview: overview
                case .processes: processList
                case .logs: OperationsLogViewer(session: session, query: .init())
                case .metrics: OperationsMetricsView(metrics: session.snapshot?.metrics ?? [])
                case .kubernetes: kubernetesBrowser
                case .console: OperationsConsole(session: session)
                case .activity: activity
                }
            }
            .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
            }
        }
    }

    private var overview: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.snapshot?.platform ?? "Platform unavailable").font(.subheadline)
                    LabeledContent("Uptime", value: session.snapshot?.uptime ?? "—")
                    LabeledContent("Processes", value: "\(session.snapshot?.processes.count ?? 0)")
                    if let observed = session.snapshot?.observedAt {
                        Text("Snapshot: \(observed.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary)
                    }
                }.operationsCard()
                if session.agent?.kubernetes == true {
                    let pods = session.snapshot?.resources.filter { $0.kind == .pods } ?? []
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Kubernetes investigation").font(.headline)
                        Text("\(pods.filter { $0.status != "Running" }.count) pods need attention. Inspect container logs, related events, and workload readiness.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Inspect Kubernetes", systemImage: "shippingbox") { area = .kubernetes }
                    }.operationsCard()
                }
                OperationsMetricsView(metrics: Array((session.snapshot?.metrics ?? []).prefix(4)), scrollable: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.visible)
    }

    private var processList: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search name, PID, user or command", text: $search).textFieldStyle(.roundedBorder)
                Picker("Sort processes", selection: $processSort) {
                    ForEach(["CPU", "Memory", "PID"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(processes) { process in
                        Button { selectedProcess = process } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(process.name).font(.subheadline.weight(.medium)); Spacer(); Text("PID \(process.id)").font(.caption) }
                                Text("\(process.user) · \(process.state)").font(.caption).foregroundStyle(.secondary)
                                Text("CPU \(process.cpuPercent.formatted())% · RAM \((process.memoryBytes / 1_048_576).formatted(.number.precision(.fractionLength(0)))) MiB")
                                    .font(.caption.monospacedDigit())
                            }.operationsCard()
                        }.buttonStyle(.plain)
                    }
                    if processes.isEmpty { ContentUnavailableView.search(text: search) }
                }
            }
        }
    }

    private var kubernetesBrowser: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Resource", selection: $kind) {
                    ForEach(KubernetesResourceKind.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu)
                Spacer()
                Picker("Namespace", selection: $namespace) {
                    Text("All namespaces").tag("All namespaces")
                    ForEach(Array(Set(session.snapshot?.resources.compactMap(\.namespace) ?? [])).sorted(), id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
            }
            TextField("Search resources or status", text: $search).textFieldStyle(.roundedBorder)
            if kind == .pods {
                OperationsPodTable(pods: resources, resources: session.snapshot?.resources ?? [],
                                   observedAt: session.snapshot?.observedAt ?? Date())
            } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(resources) { resource in
                        NavigationLink(value: resource) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(resource.name).font(.subheadline.weight(.medium)); Spacer(); Image(systemName: "chevron.right").font(.caption2) }
                                Text("\(resource.namespace ?? "Cluster scope") · \(resource.status)").font(.caption).foregroundStyle(.secondary)
                                if let ready = resource.ready, let desired = resource.desired {
                                    Text("Ready \(ready) / \(desired)" + (resource.restarts.map { " · Restarts \($0)" } ?? "")).font(.caption.monospacedDigit())
                                }
                            }.operationsCard()
                        }.buttonStyle(.plain)
                    }
                    if resources.isEmpty { ContentUnavailableView("No matching resources", systemImage: "shippingbox") }
                }
            }
            }
        }
    }

    private var activity: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(session.activity) { receipt in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(receipt.summary).font(.subheadline.weight(.medium))
                        Text(receipt.time, style: .time).font(.caption).foregroundStyle(.secondary)
                        Text(receipt.output).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }.operationsCard()
                }
                if session.activity.isEmpty { ContentUnavailableView("No operations yet", systemImage: "clock.arrow.circlepath") }
            }
        }
    }
}

extension View {
    func operationsCard() -> some View {
        padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct OperationsMetricsView: View {
    let metrics: [OperationsMetric]
    var scrollable = true
    @State private var minutes = 20
    var body: some View {
        Group {
            if scrollable { ScrollView { content } }
            else { content }
        }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
                Picker("History window", selection: $minutes) {
                    Text("5 min").tag(5); Text("15 min").tag(15); Text("20 min").tag(20)
                }.pickerStyle(.segmented)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(metrics) { metric in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(metric.title).font(.caption).foregroundStyle(.secondary)
                            Text("\(metric.value.formatted(.number.precision(.fractionLength(0...1)))) \(metric.unit)")
                                .font(.title2.weight(.light)).monospacedDigit()
                            Chart(metric.samples.filter { $0.time >= (metric.samples.last?.time ?? Date()).addingTimeInterval(-Double(minutes) * 60) }) { sample in
                                LineMark(x: .value("Time", sample.time), y: .value(metric.unit, sample.value))
                                    .foregroundStyle(Color(white: 0.7))
                            }.chartXAxis(.hidden).frame(height: 80)
                            Text("\(metric.samples.count) samples available").font(.caption2).foregroundStyle(.secondary)
                        }.operationsCard()
                    }
                }
                if metrics.isEmpty { ContentUnavailableView("Metrics unavailable", systemImage: "chart.xyaxis.line") }
        }
    }
}
