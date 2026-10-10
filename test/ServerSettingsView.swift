import SwiftUI

struct ServerSettingsView: View {
    @Binding var subtitle: String
    let titleOffset: CGFloat
    var dividerTrailingExtension: CGFloat = 0
    @State private var showingServers = false
    @State private var showingAbout = false
    @AppStorage("serverProfiles") private var savedProfiles = "[]"
    @State private var editor: ServerProfile?

    private var profiles: [ServerProfile] {
        (try? JSONDecoder().decode([ServerProfile].self, from: Data(savedProfiles.utf8))) ?? []
    }

    private func save(_ profiles: [ServerProfile]) {
        if let data = try? JSONEncoder().encode(profiles), let json = String(data: data, encoding: .utf8) {
            savedProfiles = json
        }
    }

    private func upsert(_ profile: ServerProfile) {
        var updated = profiles
        if let index = updated.firstIndex(where: { $0.id == profile.id }) {
            updated[index] = profile
        } else {
            updated.append(profile)
        }
        save(updated)
    }

    var body: some View {
        VStack(spacing: 6) {
            NodavexPageHeader(
                pageTitle: subtitle,
                titleOffset: titleOffset,
                dividerTrailingExtension: dividerTrailingExtension,
                actions: showingServers ? AnyView(
                    Button { editor = ServerProfile() } label: {
                        Label("Add agent", systemImage: "plus")
                    }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 14))
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .offset(x: dividerTrailingExtension)
                ) : nil,
                backAction: showingServers || showingAbout ? {
                    showingServers = false
                    showingAbout = false
                } : nil
            )
            NavigationStack {
            List {
                Button {
                    showingServers = true
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "server.rack")
                            .frame(width: 24)
                            .foregroundStyle(Color(white: 0.8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Servers")
                                .foregroundStyle(Color(white: 0.8))
                            Text("Connect Nodavex agents that expose metrics over HTTP/HTTPS")
                                .font(.caption)
                                .foregroundStyle(Color(white: 0.45))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Button { showingAbout = true } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle")
                            .frame(width: 24)
                            .foregroundStyle(Color(white: 0.8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("About")
                                .foregroundStyle(Color(white: 0.8))
                            Text("Your nodavex application information")
                                .font(.caption)
                                .foregroundStyle(Color(white: 0.45))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .ignoresSafeArea(.container, edges: [.top, .leading, .trailing])
            .navigationDestination(isPresented: $showingServers) { serverList }
            .navigationDestination(isPresented: $showingAbout) {
                AboutAppView()
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        }
        .tint(Color(white: 0.75))
        .ignoresSafeArea(.container, edges: [.leading, .trailing])
        .onChange(of: showingServers) { _, value in
            withAnimation(.easeInOut(duration: 0.25)) {
                subtitle = value ? "Server" : "Settings"
            }
        }
        .onChange(of: showingAbout) { _, value in
            withAnimation(.easeInOut(duration: 0.25)) {
                subtitle = value ? "About" : "Settings"
            }
        }
        .sheet(item: $editor) { profile in
            ServerEditor(profile: profile, isNew: !profiles.contains(where: { $0.id == profile.id }), save: upsert)
        }
    }

    private var serverList: some View {
        Group {
            if profiles.isEmpty {
                Text("No servers added")
                    .font(.subheadline.weight(.light))
                    .foregroundStyle(Color(white: 0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(profiles) { profile in
                        Button { editor = profile } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(profile.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color(white: 0.85))
                                    Spacer(minLength: 8)
                                    Text(profile.serverVersion.flatMap {
                                        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
                                    }.map { "Version \($0)" } ?? "Version unavailable")
                                        .font(.caption2)
                                        .foregroundStyle(Color(white: 0.45))
                                        .multilineTextAlignment(.trailing)
                                }
                                Text(profile.endpoint)
                                    .font(.caption)
                                    .foregroundStyle(Color(white: 0.5))
                                HStack(spacing: 12) {
                                    Text("Disconnected")
                                    Text(profile.enabled ?? true ? "Enabled" : "Disabled")
                                }
                                .font(.caption2)
                                .foregroundStyle(Color(white: 0.5))
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                        .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                save(profiles.filter { $0.id != profile.id })
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.black)
        .ignoresSafeArea(.container, edges: [.top, .leading, .trailing])
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct ServerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var profile: ServerProfile
    let isNew: Bool
    let save: (ServerProfile) -> Void

    private var valid: Bool {
        let host = profile.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        return !profile.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !host.isEmpty && !host.contains(where: { $0.isWhitespace })
            && !host.contains("://") && !host.contains("/")
            && Int(profile.port).map { (1...65535).contains($0) } == true
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? "Add agent" : "Edit agent")
                .font(.title3.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)

            Form {
                Section("Nodavex agent") {
                    TextField("Title", text: $profile.title)
                    Toggle("Enabled", isOn: Binding(
                        get: { profile.enabled ?? true },
                        set: { profile.enabled = $0 }
                    ))
                }
                Section("Connection details") {
                    Picker("Protocol", selection: $profile.scheme) {
                        Text("HTTP").tag("http")
                        Text("HTTPS").tag("https")
                    }
                    TextField("Host name", text: $profile.hostname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Port", text: $profile.port)
                        .keyboardType(.numberPad)
                    Toggle("Trust unverified certificate", isOn: $profile.trustUnverifiedCertificate)
                        .disabled(profile.scheme != "https")
                }
                Section("Features") {
                    Toggle("Network", isOn: $profile.network)
                    Toggle("CPU / Memory", isOn: $profile.cpuMemory)
                    Toggle("Disk", isOn: $profile.disk)
                    Toggle("Notifications", isOn: $profile.notifications)
                    Toggle("Kubernetes", isOn: Binding(
                        get: { profile.kubernetes ?? false },
                        set: { profile.kubernetes = $0 }
                    ))
                }
                if profile.kubernetes == true {
                    Section {
                        ForEach(KubernetesWidgetKind.allCases) { kind in
                            Toggle(isOn: Binding(
                                get: { profile.showsKubernetesWidget(kind) },
                                set: { enabled in
                                    var widgets = profile.kubernetesWidgets ?? KubernetesWidgetKind.allCases.map(\.rawValue)
                                    widgets.removeAll { $0 == kind.rawValue }
                                    if enabled { widgets.append(kind.rawValue) }
                                    profile.kubernetesWidgets = widgets
                                }
                            )) {
                                Label(kind.title, systemImage: kind.symbol)
                            }
                        }
                    } header: {
                        Text("Kubernetes widgets")
                    } footer: {
                        Text("The Nodavex agent gathers Kubernetes metrics and exposes them through its API. Widgets currently show labelled demo data while the API connection is being developed.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .onChange(of: profile.scheme) { old, new in
                if old == "https" && profile.port == "443" && new == "http" { profile.port = "80" }
                if old == "http" && profile.port == "80" && new == "https" { profile.port = "443" }
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(isNew ? "Add" : "Save") {
                    profile.title = profile.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    profile.hostname = profile.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
                    save(profile)
                    dismiss()
                }
                .disabled(!valid)
            }
            .buttonStyle(.glass)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Color(white: 0.09))
        .presentationBackground(Color(white: 0.09))
        .preferredColorScheme(.dark)
        .tint(Color(white: 0.75))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .statusBarHidden(true)
    }
}

private struct AboutAppView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nodavex")
                        .font(.title2.weight(.light))
                        .foregroundStyle(Color(white: 0.85))
                    Text("A compact dashboard for system administrators to monitor servers, review notifications, and manage service connections.")
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    info("Version", value: version)
                    info("Build", value: build)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Features")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(white: 0.8))
                    Text("Network traffic · CPU & memory · Disk usage · Notifications · Nodavex agents · Server actions · Kubernetes")
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Dashboard metrics currently use demonstration data. Server profiles, actions, and notification preferences are saved locally on this device. Live monitoring and HTTP/HTTPS command execution are still being developed.")
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color.black)
        .ignoresSafeArea(.container, edges: [.top, .leading, .trailing])
    }

    private func info(_ title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Color(white: 0.5))
            Spacer()
            Text(value).foregroundStyle(Color(white: 0.75))
        }
        .font(.subheadline)
    }
}
