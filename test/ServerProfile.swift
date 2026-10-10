import Foundation

struct ServerProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var enabled: Bool? = true
    var serverVersion: String? = nil
    var title = ""
    var scheme = "https"
    var hostname = ""
    var port = "443"
    var trustUnverifiedCertificate = false
    var network = true
    var cpuMemory = true
    var disk = true
    var notifications = true
    // Optional additions preserve profiles saved before Kubernetes support.
    var kubernetes: Bool? = false
    var kubernetesWidgets: [String]? = nil

    func showsKubernetesWidget(_ kind: KubernetesWidgetKind) -> Bool {
        kubernetes == true && (kubernetesWidgets?.contains(kind.rawValue) ?? true)
    }

    var endpoint: String { "\(scheme)://\(hostname):\(port)" }

    static let kubernetesSample = ServerProfile(
        id: UUID(uuidString: "92C6B019-112F-4D02-968D-364C06E30C7A")!,
        title: "Kubernetes demo agent",
        hostname: "kubernetes-demo.example",
        network: false,
        cpuMemory: false,
        disk: false,
        notifications: false,
        kubernetes: true
    )

    static func installKubernetesSample(in defaults: UserDefaults = .standard) throws {
        let installedKey = "kubernetesSampleInstalled"
        guard !defaults.bool(forKey: installedKey) else { return }
        let saved = defaults.string(forKey: "serverProfiles") ?? "[]"
        // Preserve existing profiles and never replace data that cannot be decoded.
        var profiles = try JSONDecoder().decode([ServerProfile].self, from: Data(saved.utf8))
        if !profiles.contains(where: { $0.id == kubernetesSample.id }) {
            profiles.append(kubernetesSample)
            let data = try JSONEncoder().encode(profiles)
            defaults.set(String(decoding: data, as: UTF8.self), forKey: "serverProfiles")
        }
        // A deleted or edited sample stays that way on subsequent launches.
        defaults.set(true, forKey: installedKey)
    }
}

