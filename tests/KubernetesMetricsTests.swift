import Foundation

@main
struct KubernetesMetricsTests {
    static func main() throws {
        let oldProfile: [String: Any] = [
            "id": UUID().uuidString, "title": "Existing agent", "scheme": "https",
            "hostname": "agent.example", "port": "443", "trustUnverifiedCertificate": false,
            "network": true, "cpuMemory": true, "disk": true, "notifications": true
        ]
        var profile = try JSONDecoder().decode(ServerProfile.self,
                                              from: JSONSerialization.data(withJSONObject: oldProfile))
        precondition(profile.title == "Existing agent")
        precondition(KubernetesWidgetKind.allCases.allSatisfy { !profile.showsKubernetesWidget($0) },
                     "Existing agents must keep Kubernetes disabled")
        profile.kubernetes = true
        precondition(KubernetesWidgetKind.allCases.allSatisfy { profile.showsKubernetesWidget($0) },
                     "Enabling Kubernetes initially enables all widgets")
        profile.kubernetesWidgets = [KubernetesWidgetKind.pods.rawValue]
        let saved = try JSONDecoder().decode(ServerProfile.self, from: JSONEncoder().encode(profile))
        precondition(saved.showsKubernetesWidget(.pods) && !saved.showsKubernetesWidget(.nodes))
        profile.kubernetesWidgets = []
        precondition(KubernetesWidgetKind.allCases.allSatisfy { !profile.showsKubernetesWidget($0) },
                     "An empty selection must remain empty")
        profile.kubernetes = false
        profile.kubernetesWidgets = [KubernetesWidgetKind.pods.rawValue]
        precondition(!profile.showsKubernetesWidget(.pods), "The feature toggle overrides widget selection")

        let partial = try JSONDecoder().decode(KubernetesMetrics.self, from: Data("{\"pods\":{\"pending\":0}}".utf8))
        precondition(partial.pods?.pending == 0 && partial.pods?.running == nil && partial.nodes == nil,
                     "Unavailable metrics must remain distinct from a measured zero")
        let sample = try JSONDecoder().decode(KubernetesMetrics.self,
                                             from: JSONEncoder().encode(KubernetesMetrics.demo))
        precondition(sample == .demo, "Agent metrics must survive JSON round-tripping")
        let empty = try JSONDecoder().decode(KubernetesMetrics.self, from: Data("{}".utf8))
        precondition(empty.resources == nil && empty.events == nil)
        print("Kubernetes metrics tests passed (8 scenarios).")
    }
}
