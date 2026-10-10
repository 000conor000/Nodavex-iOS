# Nodavex Operations

Operations is a single-agent investigation workspace. Select an agent with Connect; switching agents clears the previous session, selections, snapshots, and activity. Edits or removal of the active saved profile disconnect it. Late responses from a former session cannot populate the new one. Switching is disabled while submitting a mutation.

## Available in the demo

Open **Kubernetes demo agent** from the connection menu. Its data and mutations exist only in memory for that session. A reconnect resets the demo. Every screen labels the session as a demo and every mutation is labelled as a simulation; no host command, Kubernetes request, or HTTP request is issued.

- Overview of platform, uptime, process count, and resource health.
- Process search by PID/name/user/command, CPU/memory/PID ordering, process inspection, simulated graceful termination, and managed process restart.
- System logs with search, level/source filters, refresh, follow/pause polling, and export of visible lines.
- Twelve host metrics with charts and 5/15/20-minute history windows: CPU, memory, load, disk usage/read/write, I/O wait, network receive/transmit, TCP connections, swap, and file descriptors.
- Kubernetes resource browser with namespace, kind, and text filters: Pods, Deployments, DaemonSets, StatefulSets, Jobs, CronJobs, Nodes, Services, Ingresses, PVCs, ConfigMaps, Secrets metadata, Events, and Namespaces.
- Resource details, linked workload/Pod/node navigation, related events, manifest viewing/editing, container selection, current/previous container logs, and a one-shot container command console.
- Review screens for deployment/workload restarts, scaling, node cordon/uncordon/drain, supported resource deletion, manifest changes, host commands, and process termination.
- Session activity records with request IDs and operation results. These are local, temporary records rather than a durable server audit log.

Secret values are not exposed or editable. Demo manifests are abbreviated previews, not templates for real deployments. Demo logs contain a fixed history plus simulated operation events; following does not generate fake server traffic. Demo metrics are synthetic data, not production measurements.

## Live agent integration still required

The current app has no live agent endpoint contract or authentication implementation. Real profiles remain visibly unavailable until an `AgentOperationsClient` adapter is supplied to `OperationsView.liveClient`. Merely choosing an agent must not mark it connected without a successful snapshot request.

The adapter has three async methods:

| Method | Responsibility |
| --- | --- |
| `snapshot(for:)` | Return timestamped platform/uptime, process identities, metric samples, Kubernetes resource UIDs/versions/relationships, and allowed operation kinds. |
| `logs(for:query:)` | Return bounded system or container logs for the specified source, Pod UID, container, current/previous selection, and limit. Follow currently polls every three seconds while the log view is active. |
| `perform(_:on:)` | Validate and authorize the typed operation against the exact agent and target; return a definitive request receipt and output. |

All operations must be scoped and authorized by the agent, not merely by the app's enabled buttons. `allowedActions` controls presentation but does not replace per-resource/namespace authorization. Use HTTPS and the agreed authentication scheme; certificate handling must implement the saved profile's policy explicitly.

Mutation requests include a UUID idempotency key. Kubernetes requests include resource UID, namespace, and expected resource version; process termination includes both PID and start time. Validate identity and version before mutation. Manifest requests require server-side validation, immutable-target checks, and ideally dry-run/diff support. Drain must use eviction semantics and honor disruption budgets; never silently force-delete Pods. Host/container commands require separate execution authorization. Request receipts should record operator identity and be durably audited by the agent.

After a successful mutation the client refreshes the snapshot. Failure to refresh does not misreport an acknowledged operation as failed. If submission itself fails, the UI says the outcome is unconfirmed and asks the operator to check before retrying. Reuse request IDs when resolving/retrying uncertain operations.

This is a broad Operations interface with a working demo, not complete live Freelens parity. Full production integration also needs streaming interactive terminals/logs, reconnect/error handling in the transport, scalable pagination and time-series queries, Helm/release workflows, port forwarding, resource creation, persistent audit history, and granular identities/permissions. The existing interfaces leave room for these, but the app does not currently claim to provide them.

Reference: [Freelens](https://github.com/freelensapp/freelens) and its [resource/log UI interfaces](https://freelensapp.github.io/docs/extensions/reference/05-ui-components/).

## Pod table

Pods use a dense table. Headings and the sort menu order name, age, deployment replicas, deployment, namespace, status, restarts, and node in either direction. Age is measured at snapshot time; counts sort numerically and missing values stay last. Replicas show the associated deployment's ready / desired counts, sorted by desired replicas. Rows open the pod detail page.

The agent should supply optional `createdAt` (creation timestamp) and `deploymentID` (resolved Deployment UID, including through ReplicaSet ownership). Related deployment UIDs also work as a fallback. Missing values display as unavailable.

## Managed process restarts

Processes optionally advertise `restartSupported` and `managedService`. Restart is enabled only when both the process and the agent's operation capabilities permit it. The request carries the original PID and start time; the agent must validate that identity, then restart the owning service through its platform service manager or agent supervisor. Do not blindly replay the displayed command: its original environment, credentials, working directory, and supervision may be unknown. PID 1 cannot be restarted through this control.

The demo replaces the selected process with a new PID/start time, keeps the service metadata, and records old/new PIDs in the operation receipt. Repeating the same request ID returns the original receipt without restarting again.

## Session verification

```sh
swiftc test/ServerProfile.swift test/KubernetesMetrics.swift test/OperationsModels.swift test/OperationsSession.swift test/DemoOperationsClient.swift tests/OperationsSessionTests.swift -o /tmp/operations-session-tests
/tmp/operations-session-tests
```

Checks cover simulated mutation results, duplicate-request suppression, stale resource/PID rejection, container-log identity, missing live adapters, disconnect cleanup, and a late response during an agent switch.
