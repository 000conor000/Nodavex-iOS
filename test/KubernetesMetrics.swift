import Foundation

enum KubernetesWidgetKind: String, CaseIterable, Codable, Identifiable {
    case nodes = "k8sNodes", pods = "k8sPods", workloads = "k8sWorkloads"
    case resources = "k8sResources", restarts = "k8sRestarts", storage = "k8sStorage"
    case jobs = "k8sJobs", events = "k8sEvents"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .nodes: return "Node readiness"
        case .pods: return "Pod health"
        case .workloads: return "Workloads"
        case .resources: return "Cluster resources"
        case .restarts: return "Container restarts"
        case .storage: return "Persistent storage"
        case .jobs: return "Jobs"
        case .events: return "Warning events"
        }
    }

    var symbol: String {
        switch self {
        case .nodes: return "server.rack"
        case .pods: return "shippingbox"
        case .workloads: return "square.stack.3d.up"
        case .resources: return "cpu"
        case .restarts: return "arrow.clockwise"
        case .storage: return "externaldrive"
        case .jobs: return "checklist"
        case .events: return "exclamationmark.triangle"
        }
    }
}

// Proposed aggregate payload exposed by a Nodavex agent, not a Kubernetes API response.
// Missing values represent unavailable collectors; they must never be displayed as zero.
struct KubernetesMetrics: Codable, Equatable {
    var clusterName: String?
    var namespace: String? // nil = all namespaces
    var observedAt: Date?
    var nodes: Nodes?
    var pods: Pods?
    var workloads: Workloads?
    var resources: Resources?
    var restarts: Restarts?
    var storage: Storage?
    var jobs: Jobs?
    var events: Events?

    struct Nodes: Codable, Equatable {
        var total: Int?
        var ready: Int?
        var notReady: Int?
        var pressure: Int?
        var cordoned: Int?
    }
    struct Pods: Codable, Equatable {
        var running: Int?
        var pending: Int?
        var failed: Int?
        var unschedulable: Int?
        var notReady: Int?
    }
    struct Workloads: Codable, Equatable {
        var deployments: Int?
        var availableDeployments: Int?
        var readyReplicas: Int?
        var desiredReplicas: Int?
        var readyDaemonSetPods: Int?
        var desiredDaemonSetPods: Int?
        var readyStatefulSetReplicas: Int?
        var desiredStatefulSetReplicas: Int?
    }
    struct Resources: Codable, Equatable {
        var cpuUsedCores: Double?
        var cpuAllocatableCores: Double?
        var cpuRequestedCores: Double?
        var memoryUsedBytes: Double?
        var memoryAllocatableBytes: Double?
        var memoryRequestedBytes: Double?
    }
    struct Restarts: Codable, Equatable {
        var windowSeconds: Int?
        var total: Int? // Increase during the window, not the lifetime restart counter.
        var crashLooping: Int?
        var oomKilled: Int? // Containers whose last termination reason is OOMKilled.
    }
    struct Storage: Codable, Equatable {
        var boundClaims: Int?
        var pendingClaims: Int?
        var usedBytes: Double?
        var capacityBytes: Double?
    }
    struct Jobs: Codable, Equatable {
        var active: Int?
        var failed: Int?
        var succeeded: Int?
    }
    struct Events: Codable, Equatable {
        var windowSeconds: Int?
        var warnings: Int? // Observed occurrences during the window.
        var schedulingFailures: Int?
        var imagePullFailures: Int?
    }

    static let demo = KubernetesMetrics(
        clusterName: "Demo cluster",
        nodes: Nodes(total: 5, ready: 4, notReady: 1, pressure: 1, cordoned: 0),
        pods: Pods(running: 84, pending: 3, failed: 1, unschedulable: 2, notReady: 4),
        workloads: Workloads(deployments: 12, availableDeployments: 11, readyReplicas: 34,
                            desiredReplicas: 36, readyDaemonSetPods: 18, desiredDaemonSetPods: 20,
                            readyStatefulSetReplicas: 6, desiredStatefulSetReplicas: 6),
        resources: Resources(cpuUsedCores: 12.4, cpuAllocatableCores: 32, cpuRequestedCores: 18,
                             memoryUsedBytes: 27 * 1_073_741_824, memoryAllocatableBytes: 64 * 1_073_741_824,
                             memoryRequestedBytes: 40 * 1_073_741_824),
        restarts: Restarts(windowSeconds: 86_400, total: 7, crashLooping: 2, oomKilled: 1),
        storage: Storage(boundClaims: 18, pendingClaims: 1, usedBytes: 160 * 1_073_741_824,
                         capacityBytes: 256 * 1_073_741_824),
        jobs: Jobs(active: 2, failed: 1, succeeded: 24),
        events: Events(windowSeconds: 86_400, warnings: 14, schedulingFailures: 3, imagePullFailures: 2)
    )
}
