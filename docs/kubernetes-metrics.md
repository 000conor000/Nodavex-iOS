# Nodavex agent Kubernetes metrics

Saved server profiles represent Nodavex agents on any supported platform. Their HTTP/HTTPS endpoint is the agent API, which will expose host metrics and optional Kubernetes metrics. The app currently renders explicitly labelled demo values; it does not contact a cluster or collect metrics itself. The API endpoint and authentication contract are still to be defined.

`KubernetesMetrics` is a proposed JSON payload model, not a Kubernetes API resource. Each agent has its own Kubernetes feature flag and selected dashboard widgets. Existing profiles remain valid and default to Kubernetes disabled. Enabling the feature initially shows all eight widgets; selections persist independently of the feature toggle. Dashboard drag ordering also applies to these widgets.

## Metric groups

| Group | Fields | Intended source |
| --- | --- | --- |
| nodes | total, ready, notReady, pressure, cordoned | Node status conditions and spec.unschedulable |
| pods | running, pending, failed, unschedulable, notReady | Pod phases, scheduling and readiness conditions |
| workloads | deployments, availableDeployments, readyReplicas, desiredReplicas, readyDaemonSetPods, desiredDaemonSetPods, readyStatefulSetReplicas, desiredStatefulSetReplicas | Deployment, DaemonSet and StatefulSet status/spec |
| resources | cpuUsedCores, cpuAllocatableCores, cpuRequestedCores, memoryUsedBytes, memoryAllocatableBytes, memoryRequestedBytes | Resource Metrics API, node allocatable resources, effective pod requests |
| restarts | windowSeconds, total, crashLooping, oomKilled | Container status and restart-counter deltas |
| storage | boundClaims, pendingClaims, usedBytes, capacityBytes | PVC status and kubelet volume metrics where available |
| jobs | active, failed, succeeded | Counts of Jobs by status, rather than counts of their Pods |
| events | windowSeconds, warnings, schedulingFailures, imagePullFailures | Observed event occurrences in the stated collection window |

Metadata: `clusterName` (string), `namespace` (string; omit for all namespaces), `observedAt` (ISO 8601 timestamp, decoded using an ISO 8601 date strategy). An agent can publish separate payloads for different cluster/namespace scopes; this version of the dashboard previews one aggregate scope per agent.

Counts and windowSeconds are integers. Resource values are numbers: CPU in cores and memory/storage in bytes. The dashboard converts bytes to GiB. All groups and fields are optional: omit unavailable data rather than reporting zero. Zero means measured zero. Requests, usage, and allocatable capacity are separate values.

Restart totals are deltas over `windowSeconds`, requiring agent-side history; they are not lifetime restart counters. `crashLooping` counts containers currently waiting with reason CrashLoopBackOff. `oomKilled` counts containers whose last termination reason is OOMKilled and is not a 24-hour event count. Node pressure counts nodes with at least one active MemoryPressure, DiskPressure, or PIDPressure condition. Pending/failed/notReady pod counts may overlap and must not be summed into a total.

For events, deduplicate by event identity and account for increases in occurrence/series counters rather than counting event objects repeatedly. Kubernetes event retention may be shorter than the desired window, so a complete window requires the agent to retain observations. Omit window totals when the collection history is incomplete. `schedulingFailures` and `imagePullFailures` are subsets of warning occurrences.

Sources: [Kubernetes resource monitoring](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-usage-monitoring/), [Kubernetes observability](https://kubernetes.io/docs/concepts/cluster-administration/observability/), and [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics). CPU/memory usage and object-state metrics require different collectors; kube-state-metrics alone does not provide resource usage or volume usage.

## Verification

Run the model and saved-profile compatibility tests:

```sh
swiftc test/ServerProfile.swift test/KubernetesMetrics.swift tests/KubernetesMetricsTests.swift -o /tmp/kubernetes-metrics-tests
/tmp/kubernetes-metrics-tests
```
