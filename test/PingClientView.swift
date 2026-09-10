import SwiftUI
import Combine
import Darwin

struct PingConfiguration: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var alias: String
    var host: String
    var requestCount: Int
}

@MainActor
final class PingConfigurationStore: ObservableObject {
    @Published private(set) var configurations: [PingConfiguration] = []
    private let defaultsKey = "nodavex.pingConfigurations"

    init() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let saved = try? JSONDecoder().decode([PingConfiguration].self, from: data) else { return }
        configurations = saved
    }

    func add(alias: String, host: String, requestCount: Int) {
        configurations.append(PingConfiguration(
            alias: alias.trimmingCharacters(in: .whitespacesAndNewlines),
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            requestCount: requestCount
        ))
        save()
    }

    func delete(at offsets: IndexSet) {
        configurations.remove(atOffsets: offsets)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(configurations) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

struct PingLogEntry: Identifiable, Sendable {
    enum Status: Sendable { case info, success, failure }
    let id = UUID()
    let message: String
    let status: Status
}

enum ICMPPingClient {
    nonisolated static func stream(for configuration: PingConfiguration) -> AsyncStream<PingLogEntry> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                run(configuration, continuation: continuation)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    nonisolated private static func run(
        _ configuration: PingConfiguration,
        continuation: AsyncStream<PingLogEntry>.Continuation
    ) {
        guard let destination = resolveIPv4(configuration.host) else {
            continuation.yield(.init(message: "Unable to resolve \(configuration.host).", status: .failure))
            continuation.finish()
            return
        }

        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        guard descriptor >= 0 else {
            continuation.yield(.init(message: "Could not open the ICMP socket: \(posixMessage()).", status: .failure))
            continuation.finish()
            return
        }
        defer { Darwin.close(descriptor) }

        let displayAddress = numericAddress(destination)
        continuation.yield(.init(
            message: "PING \(configuration.host) (\(displayAddress)) — \(configuration.requestCount) requests",
            status: .info
        ))

        let identifier = UInt16(truncatingIfNeeded: getpid())
        var received = 0
        var totalMilliseconds = 0.0

        for request in 1...configuration.requestCount {
            if Task.isCancelled { break }

            let sequence = UInt16(truncatingIfNeeded: request)
            var packet = makeEchoRequest(identifier: identifier, sequence: sequence)
            var address = destination
            let started = ContinuousClock.now

            let sent = withUnsafePointer(to: &address) { addressPointer in
                packet.withUnsafeBytes { packetPointer in
                    addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(descriptor, packetPointer.baseAddress, packet.count, 0, $0,
                               socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }

            guard sent == packet.count else {
                continuation.yield(.init(message: "icmp_seq=\(request) send failed: \(posixMessage())", status: .failure))
                continue
            }

            if waitForReply(descriptor: descriptor, identifier: identifier, sequence: sequence, timeoutMilliseconds: 1_500) {
                let duration = started.duration(to: .now)
                let milliseconds = (Double(duration.components.seconds) * 1_000)
                    + (Double(duration.components.attoseconds) / 1_000_000_000_000_000)
                received += 1
                totalMilliseconds += milliseconds
                continuation.yield(.init(
                    message: String(format: "64 bytes from %@: icmp_seq=%d time=%.2f ms", displayAddress, request, milliseconds),
                    status: .success
                ))
            } else {
                continuation.yield(.init(message: "Request timeout for icmp_seq \(request)", status: .failure))
            }

            if request < configuration.requestCount && !Task.isCancelled {
                Thread.sleep(forTimeInterval: 0.45)
            }
        }

        guard !Task.isCancelled else {
            continuation.yield(.init(message: "Ping cancelled.", status: .info))
            continuation.finish()
            return
        }

        let loss = Int((Double(configuration.requestCount - received) / Double(configuration.requestCount) * 100).rounded())
        let average = received == 0 ? 0 : totalMilliseconds / Double(received)
        continuation.yield(.init(
            message: String(format: "--- %@ statistics ---\n%d transmitted, %d received, %d%% packet loss, avg %.2f ms",
                            configuration.host, configuration.requestCount, received, loss, average),
            status: received > 0 ? .info : .failure
        ))
        continuation.finish()
    }

    nonisolated private static func resolveIPv4(_ host: String) -> sockaddr_in? {
        let normalizedHost = host
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var numericAddress = sockaddr_in()
        numericAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        numericAddress.sin_family = sa_family_t(AF_INET)
        let parsedNumericAddress = normalizedHost.withCString {
            inet_pton(AF_INET, $0, &numericAddress.sin_addr)
        }
        if parsedNumericAddress == 1 {
            return numericAddress
        }

        var hints = addrinfo()
        hints.ai_flags = AI_ADDRCONFIG
        hints.ai_family = AF_INET
        // Address resolution must not be constrained to ICMP. Darwin rejects
        // SOCK_DGRAM + IPPROTO_ICMP here with EAI_BADHINTS.
        hints.ai_socktype = 0
        hints.ai_protocol = 0
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(normalizedHost, nil, &hints, &result) == 0, let result else { return nil }
        defer { freeaddrinfo(result) }
        guard let address = result.pointee.ai_addr else { return nil }
        return address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
    }

    nonisolated private static func numericAddress(_ address: sockaddr_in) -> String {
        var address = address
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &buffer,
                            socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
            }
        }
        return result == 0 ? String(cString: buffer) : "unknown"
    }

    nonisolated private static func makeEchoRequest(identifier: UInt16, sequence: UInt16) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 64)
        packet[0] = 8
        packet[4] = UInt8(identifier >> 8)
        packet[5] = UInt8(identifier & 0xff)
        packet[6] = UInt8(sequence >> 8)
        packet[7] = UInt8(sequence & 0xff)
        for index in 8..<packet.count { packet[index] = UInt8(truncatingIfNeeded: index) }
        let checksum = internetChecksum(packet)
        packet[2] = UInt8(checksum >> 8)
        packet[3] = UInt8(checksum & 0xff)
        return packet
    }

    nonisolated private static func internetChecksum(_ bytes: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var index = 0
        while index + 1 < bytes.count {
            sum += UInt32(bytes[index]) << 8 | UInt32(bytes[index + 1])
            index += 2
        }
        if index < bytes.count { sum += UInt32(bytes[index]) << 8 }
        while sum > 0xffff { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum)
    }

    nonisolated private static func waitForReply(
        descriptor: Int32,
        identifier: UInt16,
        sequence: UInt16,
        timeoutMilliseconds: Int32
    ) -> Bool {
        let deadline = Date().addingTimeInterval(Double(timeoutMilliseconds) / 1_000)
        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)

        while !Task.isCancelled {
            let milliseconds = max(0, Int32(deadline.timeIntervalSinceNow * 1_000))
            if milliseconds == 0 || poll(&pollDescriptor, 1, milliseconds) <= 0 { return false }

            var buffer = [UInt8](repeating: 0, count: 2_048)
            let capacity = buffer.count
            let count = buffer.withUnsafeMutableBytes { recv(descriptor, $0.baseAddress, capacity, 0) }
            guard count >= 8 else { continue }
            let offset = (buffer[0] >> 4) == 4 ? Int(buffer[0] & 0x0f) * 4 : 0
            guard count >= offset + 8 else { continue }

            let replyIdentifier = UInt16(buffer[offset + 4]) << 8 | UInt16(buffer[offset + 5])
            let replySequence = UInt16(buffer[offset + 6]) << 8 | UInt16(buffer[offset + 7])
            if buffer[offset] == 0 && replyIdentifier == identifier && replySequence == sequence { return true }
        }
        return false
    }

    nonisolated private static func posixMessage() -> String { String(cString: strerror(errno)) }
}

struct PingClientView: View {
    @StateObject private var store = PingConfigurationStore()
    @Binding var showingAddConfiguration: Bool
    @State private var activeConfiguration: PingConfiguration?
    @State private var logEntries: [PingLogEntry] = []
    @State private var isPinging = false
    @State private var pingTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Ping")
                    .font(.title2.weight(.semibold))
                Spacer()
                if activeConfiguration == nil {
                    Button { showingAddConfiguration = true } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .tint(Color("ButtonColor"))
                    .accessibilityLabel("Add ping configuration")
                }
            }

            ZStack {
                if let activeConfiguration {
                    logView(for: activeConfiguration)
                } else if store.configurations.isEmpty {
                    ContentUnavailableView("No Ping Configurations", systemImage: "dot.radiowaves.left.and.right",
                                           description: Text("Tap + to save an IP address, domain, or FQDN."))
                } else {
                    List {
                        ForEach(store.configurations) { configuration in
                            Button { startPing(configuration) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(configuration.alias).font(.headline)
                                    Text("\(configuration.host) • \(configuration.requestCount) requests")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: store.delete)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .sheet(isPresented: $showingAddConfiguration) {
            AddPingConfigurationView { alias, host, count in
                store.add(alias: alias, host: host, requestCount: count)
            }
        }
        .onDisappear { pingTask?.cancel() }
    }

    private func logView(for configuration: PingConfiguration) -> some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    pingTask?.cancel()
                    activeConfiguration = nil
                    logEntries = []
                    isPinging = false
                } label: { Label("Configurations", systemImage: "chevron.left") }
                Spacer()
                if isPinging { ProgressView() }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(logEntries) { entry in
                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(color(for: entry.status))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(16)
                }
                .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
                .onChange(of: logEntries.count) {
                    guard let last = logEntries.last else { return }
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            Button(isPinging ? "Stop" : "Ping Again") {
                if isPinging { pingTask?.cancel(); isPinging = false }
                else { startPing(configuration) }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color("ButtonColor"))
        }
        .padding(.horizontal, 20)
    }

    private func startPing(_ configuration: PingConfiguration) {
        pingTask?.cancel()
        activeConfiguration = configuration
        logEntries = []
        isPinging = true
        pingTask = Task {
            for await entry in ICMPPingClient.stream(for: configuration) {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.22)) { logEntries.append(entry) }
            }
            if !Task.isCancelled { isPinging = false }
        }
    }

    private func color(for status: PingLogEntry.Status) -> Color {
        switch status {
        case .info: return .white.opacity(0.85)
        case .success: return .green
        case .failure: return .red
        }
    }
}

private struct AddPingConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var alias = ""
    @State private var host = ""
    @State private var requestCount = 4
    let onSave: (String, String, Int) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Configuration") {
                    TextField("Name or alias", text: $alias)
                    TextField("IP address, domain, or FQDN", text: $host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Stepper("Ping requests: \(requestCount)", value: $requestCount, in: 1...100)
                }
            }
            .navigationTitle("New Ping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(alias, host, requestCount); dismiss() }
                        .disabled(alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
