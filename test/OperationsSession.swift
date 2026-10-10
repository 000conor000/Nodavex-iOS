import Foundation
import Observation

// Implement this adapter once authentication and the agent's HTTP/HTTPS contract exist.
@MainActor protocol AgentOperationsClient {
    func snapshot(for agent: ServerProfile) async throws -> OperationsSnapshot
    func logs(for agent: ServerProfile, query: OperationsLogQuery) async throws -> [OperationsLogEntry]
    func perform(_ action: OperationsAction, on agent: ServerProfile) async throws -> OperationsReceipt
}

@MainActor @Observable final class OperationsSession {
    private(set) var agent: ServerProfile?
    private(set) var snapshot: OperationsSnapshot?
    private(set) var isDemo = false
    private(set) var loading = false
    private(set) var performing = false
    private(set) var activity: [OperationsReceipt] = []
    var error: String?
    private var client: (any AgentOperationsClient)?
    private var generation = UUID()

    func disconnect() {
        generation = UUID()
        agent = nil
        snapshot = nil
        client = nil
        activity = []
        loading = false
        performing = false
        error = nil
        isDemo = false
    }

    func connect(_ target: ServerProfile, liveClient: (any AgentOperationsClient)? = nil) async {
        guard !performing else { return }
        disconnect()
        guard target.enabled ?? true else {
            error = "Enable this agent in Settings before connecting."
            return
        }
        isDemo = target.id == ServerProfile.kubernetesSample.id
            && target.hostname == ServerProfile.kubernetesSample.hostname
        guard isDemo || liveClient != nil else {
            error = OperationsError.unavailable.localizedDescription
            return
        }
        agent = target
        client = isDemo ? DemoOperationsClient(kubernetes: target.kubernetes == true) : liveClient
        let token = generation
        await refresh()
        guard token == generation else { return }
        if snapshot == nil { agent = nil; client = nil }
    }

    func refresh() async {
        guard let agent, let client, !loading, !performing else { return }
        let token = generation
        loading = true
        do {
            let updated = try await client.snapshot(for: agent)
            guard token == generation else { return }
            snapshot = updated
            error = nil
        } catch {
            guard token == generation else { return }
            self.error = error.localizedDescription
        }
        if token == generation { loading = false }
    }

    func logs(_ query: OperationsLogQuery) async throws -> [OperationsLogEntry] {
        guard let agent, let client else { throw OperationsError.unavailable }
        let token = generation
        let entries = try await client.logs(for: agent, query: query)
        guard token == generation else { throw OperationsError.staleSession }
        return entries
    }

    func perform(_ action: OperationsAction, expectedAgentID: UUID) async {
        guard let agent, agent.id == expectedAgentID, let client, !performing, !loading else {
            error = OperationsError.staleSession.localizedDescription
            return
        }
        guard snapshot?.allowedActions.contains(action.kind) == true else {
            error = OperationsError.invalidAction.localizedDescription
            return
        }
        let token = generation
        performing = true
        do {
            let receipt = try await client.perform(action, on: agent)
            guard token == generation else { return }
            activity.insert(receipt, at: 0)
            if activity.count > 100 { activity.removeLast() }
            error = nil
            do {
                let updated = try await client.snapshot(for: agent)
                guard token == generation else { return }
                snapshot = updated
            } catch {
                guard token == generation else { return }
                self.error = "Operation confirmed, but the refreshed snapshot could not be loaded: \(error.localizedDescription)"
            }
        } catch {
            guard token == generation else { return }
            self.error = "Operation could not be confirmed: \(error.localizedDescription). Check the target before retrying."
        }
        if token == generation { performing = false }
    }
}
