import Foundation

@MainActor final class DemoOperationsClient: AgentOperationsClient {
    private var data: OperationsSnapshot
    private var receipts: [UUID: OperationsReceipt] = [:]
    private var operationLogs: [OperationsLogEntry] = []

    init(kubernetes: Bool) {
        let now = Date()
        var processes = [
            OperationsProcess(id: 1, startedAt: now.addingTimeInterval(-604_800), name: "systemd", user: "root", state: "Sleeping", cpuPercent: 0.1, memoryBytes: 14_000_000, threads: 1, command: "/sbin/init"),
            OperationsProcess(id: 248, startedAt: now.addingTimeInterval(-80_000), name: "nodavex-agent", user: "nodavex", state: "Running", cpuPercent: 1.2, memoryBytes: 64_000_000, threads: 8, command: "/usr/bin/nodavex-agent --config /etc/nodavex/config.yaml"),
            OperationsProcess(id: 502, startedAt: now.addingTimeInterval(-75_000), name: "kubelet", user: "root", state: "Running", cpuPercent: 8.4, memoryBytes: 280_000_000, threads: 24, command: "/usr/bin/kubelet --config /var/lib/kubelet/config.yaml"),
            OperationsProcess(id: 731, startedAt: now.addingTimeInterval(-3_600), name: "python3", user: "app", state: "Running", cpuPercent: 38.2, memoryBytes: 920_000_000, threads: 12, command: "python3 /opt/worker/process_queue.py"),
            OperationsProcess(id: 902, startedAt: now.addingTimeInterval(-7_200), name: "containerd", user: "root", state: "Sleeping", cpuPercent: 2.1, memoryBytes: 180_000_000, threads: 16, command: "/usr/bin/containerd")
        ]
        for index in processes.indices where processes[index].id != 1 {
            processes[index].restartSupported = true
            processes[index].managedService = processes[index].name == "python3" ? "nodavex-worker" : processes[index].name
        }
        let definitions: [(String, String, String, Double)] = [
            ("cpu", "CPU usage", "%", 42), ("memory", "Memory used", "GiB", 27),
            ("load", "Load average · 1 minute", "", 3.8), ("disk", "Disk used", "%", 64),
            ("read", "Disk reads", "MiB/s", 12), ("write", "Disk writes", "MiB/s", 8),
            ("iowait", "CPU I/O wait", "%", 4), ("networkRx", "Network receive", "Mbps", 18.6),
            ("networkTx", "Network transmit", "Mbps", 2.4), ("connections", "TCP connections", "", 148),
            ("swap", "Swap used", "GiB", 0.4), ("descriptors", "Open file descriptors", "", 1_248)
        ]
        let metrics = definitions.map { id, title, unit, value in
            OperationsMetric(id: id, title: title, unit: unit, value: value,
                samples: (0..<20).map { index in
                    .init(time: now.addingTimeInterval(Double(index - 19) * 60),
                          value: value * (0.85 + sin(Double(index) * 0.6) * 0.15))
                })
        }
        data = OperationsSnapshot(observedAt: now, platform: "Linux · Ubuntu · amd64 (demo)",
                                  uptime: "7 days, 4 hours", processes: processes, metrics: metrics,
                                  resources: kubernetes ? Self.resources : [], allowedActions: OperationsAction.Kind.allCases)
    }

    func snapshot(for agent: ServerProfile) async throws -> OperationsSnapshot { data }

    func logs(for agent: ServerProfile, query: OperationsLogQuery) async throws -> [OperationsLogEntry] {
        if query.source == "pod" {
            guard let resource = data.resources.first(where: { $0.id == query.resourceID && $0.kind == .pods }),
                  let container = query.container, resource.containers.contains(container) else {
                throw OperationsError.staleResource
            }
            let messages = query.previous
                ? ["Starting container", "Configuration error: DATABASE_URL is missing", "Process exited with code 1"]
                : ["Starting \(container)", "Loading application configuration", "Waiting for database connection", "Connection refused; retrying in 5s"]
            return messages.enumerated().map { index, message in
                OperationsLogEntry(id: "\(resource.id)-\(container)-\(query.previous)-\(index)",
                    time: data.observedAt.addingTimeInterval(Double(index - messages.count) * 15),
                    level: index > 1 ? "Error" : "Info", source: container, message: message,
                    resourceID: resource.id, container: container, previous: query.previous)
            }
        }
        let messages = [
            ("Info", "systemd", "Started Nodavex agent."),
            ("Warning", "kubelet", "Node memory pressure detected on worker-02."),
            ("Error", "containerd", "Container api exited with code 1; restart scheduled."),
            ("Info", "sshd", "Operations session opened."),
            ("Warning", "kernel", "Disk latency exceeded the warning threshold.")
        ]
        let entries = messages.enumerated().map { index, item in
            OperationsLogEntry(id: "system-\(index)", time: data.observedAt.addingTimeInterval(Double(index - 5) * 30),
                               level: item.0, source: item.1, message: item.2)
        }
        return Array((entries + operationLogs).suffix(max(0, min(query.limit, 5_000))))
    }

    func perform(_ action: OperationsAction, on agent: ServerProfile) async throws -> OperationsReceipt {
        if let receipt = receipts[action.id] { return receipt }
        guard data.allowedActions.contains(action.kind) else { throw OperationsError.invalidAction }
        var output = "Demo simulation only. No command was sent to a server or Kubernetes cluster."
        switch action.kind {
        case .terminateProcess, .restartProcess:
            guard let index = data.processes.firstIndex(where: { $0.id == action.processID && $0.startedAt == action.processStartedAt }),
                  data.processes[index].id != 1 else { throw OperationsError.staleResource }
            if action.kind == .restartProcess {
                let old = data.processes[index]
                guard old.restartSupported == true else { throw OperationsError.invalidAction }
                let replacementID = (data.processes.map(\.id).max() ?? 0) + 1
                data.processes[index] = OperationsProcess(id: replacementID, startedAt: Date(), name: old.name,
                    user: old.user, state: "Running", cpuPercent: 0, memoryBytes: old.memoryBytes, threads: old.threads,
                    command: old.command, restartSupported: old.restartSupported, managedService: old.managedService)
                output += "\nRestarted \(old.managedService ?? old.name): PID \(old.id) → PID \(replacementID)."
            } else {
                data.processes.remove(at: index)
            }
        case .runCommand:
            guard let command = action.command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw OperationsError.invalidAction
            }
            if let resourceID = action.resourceID {
                guard let pod = data.resources.first(where: { $0.id == resourceID && $0.namespace == action.namespace && $0.kind == .pods }),
                      pod.version == action.expectedVersion, let container = action.container, pod.containers.contains(container) else {
                    throw OperationsError.staleResource
                }
            }
            output += "\nRequested command: \(command)\nReal command output requires the agent API."
        default:
            guard let index = data.resources.firstIndex(where: { $0.id == action.resourceID && $0.namespace == action.namespace }),
                  data.resources[index].version == action.expectedVersion else { throw OperationsError.staleResource }
            let resource = data.resources[index]
            switch action.kind {
            case .restartWorkload:
                guard resource.kind.supportsRestart else { throw OperationsError.invalidAction }
                data.resources[index].status = "Rollout requested (demo)"
            case .scaleWorkload:
                guard resource.kind.supportsScale, let replicas = action.replicas, (0...1_000).contains(replicas) else {
                    throw OperationsError.invalidAction
                }
                data.resources[index].desired = replicas
                data.resources[index].ready = min(resource.ready ?? 0, replicas)
                data.resources[index].status = "Scaling requested (demo)"
            case .cordonNode, .uncordonNode, .drainNode:
                guard resource.kind == .nodes else { throw OperationsError.invalidAction }
                data.resources[index].status = action.kind == .uncordonNode ? "Ready" : action.kind == .cordonNode ? "Cordoned (demo)" : "Drain requested (demo)"
            case .applyManifest:
                guard resource.kind != .secrets, let manifest = action.manifest, !manifest.isEmpty else {
                    throw OperationsError.invalidAction
                }
                data.resources[index].manifest = manifest
                data.resources[index].status = "Manifest updated (demo)"
            case .deleteResource:
                guard ![.events, .namespaces, .secrets, .nodes].contains(resource.kind) else { throw OperationsError.invalidAction }
                data.resources.remove(at: index)
            default: throw OperationsError.invalidAction
            }
            if let updatedIndex = data.resources.firstIndex(where: { $0.id == resource.id }) {
                data.resources[updatedIndex].version = String((Int(resource.version) ?? 0) + 1)
            }
        }
        data.observedAt = Date()
        let receipt = OperationsReceipt(id: action.id, time: Date(), summary: "\(action.kind.title): \(action.target)", output: output, isDemo: true)
        receipts[action.id] = receipt
        operationLogs.append(.init(id: action.id.uuidString, time: receipt.time, level: "Info", source: "nodavex-operations", message: receipt.summary + " (simulated)"))
        return receipt
    }

    private static var resources: [OperationsResource] {
        var entries: [OperationsResource] = [
            .init(id: "pod-api", kind: .pods, name: "api-7c9d-2x", namespace: "production", status: "CrashLoopBackOff", ready: 0, desired: 1, restarts: 7, node: "worker-02", containers: ["api", "sidecar"], details: ["Owner": "Deployment/api", "Image": "example/api:1.4", "Last exit": "1", "Reason": "Configuration error"]),
            .init(id: "pod-web", kind: .pods, name: "web-84cf-6k", namespace: "production", status: "Running", ready: 1, desired: 1, restarts: 0, node: "worker-01", containers: ["web"]),
            .init(id: "deploy-api", kind: .deployments, name: "api", namespace: "production", status: "Degraded", ready: 2, desired: 3, details: ["Strategy": "RollingUpdate", "Image": "example/api:1.4"]),
            .init(id: "deploy-web", kind: .deployments, name: "web", namespace: "production", status: "Available", ready: 3, desired: 3),
            .init(id: "node-01", kind: .nodes, name: "worker-01", namespace: nil, status: "Ready", details: ["CPU allocatable": "8 cores", "Memory allocatable": "16 GiB", "Pressure": "None"]),
            .init(id: "node-02", kind: .nodes, name: "worker-02", namespace: nil, status: "MemoryPressure", details: ["CPU allocatable": "8 cores", "Memory allocatable": "16 GiB", "Pressure": "MemoryPressure"])
        ]
        let definitions: [(KubernetesResourceKind, String, String?, String)] = [
            (.daemonSets, "node-exporter", "kube-system", "Ready"), (.statefulSets, "database", "production", "Ready"),
            (.jobs, "backup-20261010", "production", "Complete"), (.cronJobs, "nightly-backup", "production", "Scheduled"),
            (.services, "api", "production", "ClusterIP"), (.ingresses, "public-api", "production", "Available"),
            (.storage, "database-data", "production", "Bound"), (.configMaps, "api-config", "production", "Available"),
            (.secrets, "database-credentials", "production", "Metadata only"),
            (.events, "api-backoff", "production", "Warning"), (.namespaces, "production", nil, "Active"),
            (.namespaces, "kube-system", nil, "Active")
        ]
        entries += definitions.map { kind, name, namespace, status in
            OperationsResource(id: "\(kind.rawValue)-\(name)", kind: kind, name: name, namespace: namespace,
                status: status, ready: kind.supportsRestart ? 3 : nil, desired: kind.supportsRestart ? 3 : nil,
                details: kind == .events ? ["Reason": "BackOff", "Message": "Back-off restarting failed container api", "Object": "Pod/api-7c9d-2x"] : [:])
        }
        let services = ["auth", "billing", "catalog", "checkout", "gateway", "inventory", "mailer", "payments", "search", "worker"]
        for number in 1...50 {
            let name = "\(services[(number - 1) % services.count])-\(String(format: "%02d", number))"
            let namespace = number % 3 == 0 ? "staging" : "production"
            let deploymentID = "demo-deploy-\(number)"
            let podID = "demo-pod-\(number)"
            let nodeID = number.isMultiple(of: 2) ? "node-01" : "node-02"
            let nodeName = number.isMultiple(of: 2) ? "worker-01" : "worker-02"
            let status = number.isMultiple(of: 11) ? "CrashLoopBackOff" : number.isMultiple(of: 7) ? "Pending" : "Running"
            let replicas = 1 + number % 10
            let image = "example/\(services[(number - 1) % services.count]):1.\(number % 5)"
            entries.append(.init(id: deploymentID, kind: .deployments, name: name, namespace: namespace,
                status: status == "Running" ? "Available" : "Degraded",
                ready: status == "Running" ? replicas : replicas - 1, desired: replicas,
                relatedIDs: [podID], details: ["Strategy": "RollingUpdate", "Image": image]))
            entries.append(.init(id: podID, kind: .pods, name: "\(name)-7c9d-\(number)", namespace: namespace,
                status: status, ready: status == "Running" ? 1 : 0, desired: 1,
                restarts: status == "CrashLoopBackOff" ? number % 9 + 1 : number % 3,
                node: nodeName, containers: ["app"], relatedIDs: [deploymentID, nodeID],
                details: ["Owner": "Deployment/\(name)", "Image": image], deploymentID: deploymentID))
        }
        entries.append(.init(id: "Namespaces-staging", kind: .namespaces, name: "staging", namespace: nil, status: "Active"))
        for index in entries.indices {
            let resource = entries[index]
            entries[index].createdAt = Date().addingTimeInterval(-Double(index + 1) * 3_600)
            switch resource.id {
            case "pod-api": entries[index].relatedIDs = ["deploy-api", "node-02"]; entries[index].deploymentID = "deploy-api"
            case "pod-web": entries[index].relatedIDs = ["deploy-web", "node-01"]; entries[index].deploymentID = "deploy-web"
            case "deploy-api": entries[index].relatedIDs = ["pod-api"]
            case "deploy-web": entries[index].relatedIDs = ["pod-web"]
            case "Events-api-backoff": entries[index].relatedIDs = ["pod-api", "deploy-api"]
            default: break
            }
            let kind = resource.kind == .pods ? "Pod" : resource.kind == .deployments ? "Deployment" : resource.kind == .nodes ? "Node" : resource.kind.rawValue
            entries[index].manifest = "# Demo manifest preview\nkind: \(kind)\nmetadata:\n  name: \(resource.name)\n" + (resource.namespace.map { "  namespace: \($0)\n" } ?? "")
            if resource.kind == .secrets { entries[index].manifest += "# Secret values are not exposed.\n" }
        }
        return entries
    }
}
