import Foundation

@main
struct PodTableSortTests {
    static func main() throws {
        let small = OperationsResource(id: "small", kind: .deployments, name: "zeta", namespace: "production", status: "Ready", desired: 2)
        let large = OperationsResource(id: "large", kind: .deployments, name: "alpha", namespace: "production", status: "Ready", desired: 10)
        let a = OperationsResource(id: "a", kind: .pods, name: "Alpha", namespace: "production", status: "Running", restarts: 2, relatedIDs: ["small"], createdAt: Date(timeIntervalSince1970: 100))
        let b = OperationsResource(id: "b", kind: .pods, name: "beta", namespace: "production", status: "Pending", restarts: 10, createdAt: Date(timeIntervalSince1970: 200), deploymentID: "large")
        let missing = OperationsResource(id: "missing", kind: .pods, name: "unknown", namespace: "production", status: "Unknown")
        let pods = [missing, b, a]
        func ids(_ column: PodTableColumn, ascending: Bool = true) -> [String] {
            column.sorted(pods, resources: pods + [small, large], ascending: ascending).map(\.id)
        }
        precondition(ids(.name) == ["a", "b", "missing"])
        precondition(ids(.age) == ["b", "a", "missing"], "Age sorts youngest first")
        precondition(ids(.age, ascending: false) == ["a", "b", "missing"])
        precondition(ids(.replicas) == ["a", "b", "missing"], "Counts must sort numerically")
        precondition(ids(.replicas, ascending: false) == ["b", "a", "missing"])
        precondition(ids(.deployment) == ["b", "a", "missing"])
        precondition(ids(.restarts) == ["a", "b", "missing"])
        precondition(ids(.restarts, ascending: false) == ["b", "a", "missing"])
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as! [String: Any]
        legacy.removeValue(forKey: "createdAt")
        legacy.removeValue(forKey: "deploymentID")
        let decoded = try JSONDecoder().decode(OperationsResource.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(decoded.createdAt == nil && decoded.deploymentID == nil)
        print("Pod table sorting tests passed")
    }
}
