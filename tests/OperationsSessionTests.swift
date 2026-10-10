import Foundation

@main
struct OperationsSessionTests {
    @MainActor static func main() async throws {
        let agent = ServerProfile.kubernetesSample
        let client = DemoOperationsClient(kubernetes: true)
        let first = try await client.snapshot(for: agent)
        let demoPods = first.resources.filter { $0.kind == .pods }
        let demoDeployments = first.resources.filter { $0.kind == .deployments }
        precondition(demoPods.count == 52 && demoDeployments.count == 52)
        precondition(Set(first.resources.map(\.id)).count == first.resources.count, "Demo resource UIDs must be unique")
        precondition(demoPods.allSatisfy { pod in
            pod.createdAt != nil && demoDeployments.contains { $0.id == pod.deploymentID && $0.namespace == pod.namespace && $0.relatedIDs.contains(pod.id) }
        }, "Every demo pod must link to its deployment in the same namespace")
        let workload = first.resources.first { $0.id == "deploy-api" }!
        let scale = OperationsAction(kind: .scaleWorkload, target: workload.name, namespace: workload.namespace,
                                     resourceID: workload.id, expectedVersion: workload.version, replicas: 5)
        let receipt = try await client.perform(scale, on: agent)
        let retry = try await client.perform(scale, on: agent)
        precondition(receipt.id == retry.id && receipt.isDemo, "Retries must not execute a mutation twice")
        let scaled = try await client.snapshot(for: agent)
        precondition(scaled.resources.first { $0.id == workload.id }?.desired == 5)
        precondition(scaled.resources.first { $0.id == workload.id }?.version == "2")
        do {
            _ = try await client.perform(.init(kind: .restartWorkload, target: workload.name, namespace: workload.namespace,
                                               resourceID: workload.id, expectedVersion: "1"), on: agent)
            preconditionFailure("A stale resource version must be rejected")
        } catch OperationsError.staleResource { }

        let process = first.processes.first { $0.id == 731 }!
        let restartTarget = first.processes.first { $0.id == 502 }!
        let restart = OperationsAction(kind: .restartProcess, target: restartTarget.name,
                                       processID: restartTarget.id, processStartedAt: restartTarget.startedAt)
        let restartedReceipt = try await client.perform(restart, on: agent)
        let restartedSnapshot = try await client.snapshot(for: agent)
        let replacement = restartedSnapshot.processes.first { $0.name == restartTarget.name }!
        precondition(replacement.id != restartTarget.id && replacement.startedAt != restartTarget.startedAt)
        precondition(replacement.managedService == restartTarget.managedService)
        let repeatedReceipt = try await client.perform(restart, on: agent)
        let repeatedSnapshot = try await client.snapshot(for: agent)
        precondition(repeatedReceipt.id == restartedReceipt.id)
        precondition(repeatedSnapshot.processes.first { $0.name == restartTarget.name }?.id == replacement.id,
                     "A repeated restart request must not restart the replacement again")
        do {
            _ = try await client.perform(.init(kind: .restartProcess, target: restartTarget.name,
                                               processID: restartTarget.id, processStartedAt: restartTarget.startedAt), on: agent)
            preconditionFailure("The old process identity must no longer be restartable")
        } catch OperationsError.staleResource { }
        do {
            _ = try await client.perform(.init(kind: .terminateProcess, target: process.name, processID: process.id,
                                               processStartedAt: Date.distantPast), on: agent)
            preconditionFailure("A reused PID must be rejected")
        } catch OperationsError.staleResource { }
        _ = try await client.perform(.init(kind: .terminateProcess, target: process.name, processID: process.id,
                                          processStartedAt: process.startedAt), on: agent)
        let afterTermination = try await client.snapshot(for: agent)
        precondition(!afterTermination.processes.contains { $0.id == process.id })

        let previous = try await client.logs(for: agent, query: .init(source: "pod", resourceID: "pod-api", container: "api", previous: true))
        precondition(previous.allSatisfy { $0.resourceID == "pod-api" && $0.container == "api" && $0.previous })
        do {
            _ = try await client.logs(for: agent, query: .init(source: "pod", resourceID: "pod-api", container: "nonexistent"))
            preconditionFailure("An invalid container must be rejected")
        } catch OperationsError.staleResource { }

        let session = OperationsSession()
        await session.connect(agent)
        precondition(session.agent?.id == agent.id && session.isDemo && session.snapshot != nil)
        await session.perform(scale, expectedAgentID: UUID())
        precondition(session.activity.isEmpty, "An operation must not cross agent sessions")
        session.disconnect()
        precondition(session.agent == nil && session.snapshot == nil && session.activity.isEmpty)
        var realAgent = ServerProfile()
        realAgent.title = "Real agent"; realAgent.hostname = "agent.example"
        await session.connect(realAgent)
        precondition(session.agent == nil && session.snapshot == nil && session.error != nil,
                     "An agent without an API adapter must not appear connected")

        // A slow former agent must not overwrite a newer connection's state.
        let slow = SlowOperationsClient(snapshot: first)
        let connecting = Task { await session.connect(realAgent, liveClient: slow) }
        while slow.waiting == nil { await Task.yield() }
        await session.connect(agent)
        slow.waiting?.resume(returning: first)
        await connecting.value
        precondition(session.agent?.id == agent.id && session.isDemo && session.snapshot != nil)
        print("Operations tests passed: mutations, idempotency, target identity, logs, and single-agent session isolation.")
    }
}

@MainActor private final class SlowOperationsClient: AgentOperationsClient {
    var waiting: CheckedContinuation<OperationsSnapshot, Never>?
    let data: OperationsSnapshot
    init(snapshot: OperationsSnapshot) { data = snapshot }
    func snapshot(for agent: ServerProfile) async throws -> OperationsSnapshot {
        await withCheckedContinuation { waiting = $0 }
    }
    func logs(for agent: ServerProfile, query: OperationsLogQuery) async throws -> [OperationsLogEntry] { [] }
    func perform(_ action: OperationsAction, on agent: ServerProfile) async throws -> OperationsReceipt { throw OperationsError.invalidAction }
}
