import Foundation

enum OperationsArea: String, CaseIterable, Identifiable {
    case overview = "Overview", processes = "Processes", logs = "System logs"
    case metrics = "Deep metrics", kubernetes = "Kubernetes", console = "Console", activity = "Activity"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .processes: return "cpu"
        case .logs: return "doc.text"
        case .metrics: return "chart.xyaxis.line"
        case .kubernetes: return "shippingbox"
        case .console: return "terminal"
        case .activity: return "clock.arrow.circlepath"
        }
    }
}

struct OperationsProcess: Identifiable, Codable, Hashable {
    let id: Int // PID; the start time disambiguates reused PIDs.
    let startedAt: Date
    let name: String
    let user: String
    let state: String
    let cpuPercent: Double
    let memoryBytes: Double
    let threads: Int
    let command: String
    var restartSupported: Bool? = nil
    var managedService: String? = nil
}

struct OperationsMetric: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let unit: String
    let value: Double
    let samples: [Sample]
    struct Sample: Identifiable, Codable, Hashable {
        var id: Date { time }
        let time: Date
        let value: Double
    }
}

enum KubernetesResourceKind: String, CaseIterable, Codable, Identifiable {
    case pods = "Pods", deployments = "Deployments", daemonSets = "DaemonSets"
    case statefulSets = "StatefulSets", jobs = "Jobs", cronJobs = "CronJobs"
    case nodes = "Nodes", services = "Services", ingresses = "Ingresses"
    case storage = "PersistentVolumeClaims", configMaps = "ConfigMaps", secrets = "Secrets"
    case events = "Events", namespaces = "Namespaces"
    var id: String { rawValue }
    var supportsRestart: Bool { [.deployments, .daemonSets, .statefulSets].contains(self) }
    var supportsScale: Bool { [.deployments, .statefulSets].contains(self) }
}

struct OperationsResource: Identifiable, Codable, Hashable {
    let id: String // Kubernetes UID, never the display name.
    let kind: KubernetesResourceKind
    let name: String
    let namespace: String?
    var status: String
    var version: String = "1"
    var ready: Int? = nil
    var desired: Int? = nil
    var restarts: Int? = nil
    var node: String? = nil
    var containers: [String] = []
    var relatedIDs: [String] = []
    var details: [String: String] = [:]
    var manifest: String = ""
    var createdAt: Date? = nil
    var deploymentID: String? = nil
}

enum PodTableColumn: String, CaseIterable, Identifiable {
    case name = "Name", age = "Age", replicas = "Deployment replicas", deployment = "Deployment"
    case namespace = "Namespace", status = "Status", restarts = "Restarts", node = "Node"
    var id: String { rawValue }

    func sorted(_ pods: [OperationsResource], resources: [OperationsResource], ascending: Bool) -> [OperationsResource] {
        let deployments = Dictionary(resources.filter { $0.kind == .deployments }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func deployment(_ pod: OperationsResource) -> OperationsResource? {
            pod.deploymentID.flatMap { deployments[$0] } ?? pod.relatedIDs.compactMap { deployments[$0] }.first
        }
        func compare<T: Comparable>(_ a: T?, _ b: T?) -> Int {
            // Missing metrics always appear last, in either direction.
            guard let a else { return b == nil ? 0 : 1 }
            guard let b else { return -1 }
            let result = a == b ? 0 : a < b ? -1 : 1
            return ascending ? result : -result
        }
        return pods.sorted { a, b in
            let order: Int
            switch self {
            case .name: order = compare(a.name.lowercased(), b.name.lowercased())
            // A newer creation timestamp means a smaller age.
            case .age: order = compare(a.createdAt.map { -$0.timeIntervalSince1970 }, b.createdAt.map { -$0.timeIntervalSince1970 })
            case .replicas: order = compare(deployment(a)?.desired, deployment(b)?.desired)
            case .deployment: order = compare(deployment(a)?.name.lowercased(), deployment(b)?.name.lowercased())
            case .namespace: order = compare(a.namespace?.lowercased(), b.namespace?.lowercased())
            case .status: order = compare(a.status.lowercased(), b.status.lowercased())
            case .restarts: order = compare(a.restarts, b.restarts)
            case .node: order = compare(a.node?.lowercased(), b.node?.lowercased())
            }
            if order != 0 { return order < 0 }
            if a.name != b.name { return a.name < b.name }
            return a.id < b.id
        }
    }
}

struct OperationsLogQuery: Hashable, Codable {
    var source = "system"
    var resourceID: String? = nil
    var container: String? = nil
    var previous = false
    var limit = 500
}

struct OperationsLogEntry: Identifiable, Codable, Hashable {
    let id: String
    let time: Date
    let level: String
    let source: String
    let message: String
    var resourceID: String? = nil
    var container: String? = nil
    var previous = false
}

struct OperationsSnapshot: Codable {
    var observedAt: Date
    var platform: String
    var uptime: String
    var processes: [OperationsProcess]
    var metrics: [OperationsMetric]
    var resources: [OperationsResource]
    var allowedActions: [OperationsAction.Kind]
}

struct OperationsAction: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case terminateProcess, restartProcess, restartWorkload, scaleWorkload, deleteResource
        case cordonNode, uncordonNode, drainNode, applyManifest, runCommand
        var title: String {
            switch self {
            case .terminateProcess: return "Terminate process"
            case .restartProcess: return "Restart process"
            case .restartWorkload: return "Restart workload"
            case .scaleWorkload: return "Scale workload"
            case .deleteResource: return "Delete resource"
            case .cordonNode: return "Cordon node"
            case .uncordonNode: return "Uncordon node"
            case .drainNode: return "Drain node"
            case .applyManifest: return "Apply manifest"
            case .runCommand: return "Run command"
            }
        }
    }
    var id = UUID() // Also the idempotency key for the agent API.
    let kind: Kind
    let target: String
    var namespace: String? = nil
    var resourceID: String? = nil
    var expectedVersion: String? = nil
    var processID: Int? = nil
    var processStartedAt: Date? = nil
    var replicas: Int? = nil
    var manifest: String? = nil
    var command: String? = nil
    var container: String? = nil
}

struct OperationsReceipt: Identifiable, Codable {
    let id: UUID
    let time: Date
    let summary: String
    let output: String
    let isDemo: Bool
}

enum OperationsError: LocalizedError {
    case unavailable, staleSession, staleResource, invalidAction
    var errorDescription: String? {
        switch self {
        case .unavailable: return "The live Nodavex agent API is not connected yet. Open the Kubernetes demo agent to explore Operations."
        case .staleSession: return "The active agent changed. This operation was discarded."
        case .staleResource: return "The target changed or was removed. Refresh and review it again."
        case .invalidAction: return "This operation is not supported for the selected target."
        }
    }
}
