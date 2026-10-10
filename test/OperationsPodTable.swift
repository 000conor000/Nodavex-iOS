import SwiftUI

struct OperationsPodTable: View {
    let pods: [OperationsResource]
    let resources: [OperationsResource]
    let observedAt: Date
    @State private var sort = PodTableColumn.name
    @State private var ascending = true

    private var sortedPods: [OperationsResource] {
        sort.sorted(pods, resources: resources, ascending: ascending)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(pods.count) pods").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(PodTableColumn.allCases) { column in
                        Button(column.rawValue) { select(column) }
                    }
                    Divider()
                    Button(ascending ? "Switch to descending" : "Switch to ascending") { ascending.toggle() }
                } label: {
                    Label("\(sort.rawValue) · \(ascending ? "Ascending" : "Descending")", systemImage: "arrow.up.arrow.down")
                        .font(.caption)
                }
            }
            Text("Swipe for columns · Replicas: deployment ready / desired")
                .font(.caption2).foregroundStyle(.secondary)
            if pods.isEmpty {
                ContentUnavailableView("No matching pods", systemImage: "shippingbox")
            } else {
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(PodTableColumn.allCases) { column in
                                Button { select(column) } label: {
                                    HStack(spacing: 4) {
                                        Text(column.rawValue)
                                        if sort == column {
                                            Image(systemName: ascending ? "arrow.up" : "arrow.down")
                                        }
                                    }
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .frame(width: width(column), alignment: .leading)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Sort by \(column.rawValue)")
                                .accessibilityValue(sort == column ? (ascending ? "Ascending" : "Descending") : "Unsorted")
                            }
                        }
                        .padding(.horizontal, 4)
                        Divider()
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(sortedPods) { pod in
                                    NavigationLink(value: pod) {
                                        HStack(spacing: 0) {
                                            ForEach(PodTableColumn.allCases) { column in
                                                Text(value(column, pod: pod))
                                                    .font(column == .name ? .caption2.weight(.medium) : .caption2)
                                                    .monospacedDigit()
                                                    .lineLimit(1)
                                                    .frame(width: width(column), alignment: .leading)
                                            }
                                        }
                                        .padding(.horizontal, 4).padding(.vertical, 6)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Open pod details")
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(width: PodTableColumn.allCases.reduce(CGFloat(8)) { $0 + width($1) })
                }
            }
        }
    }

    private func select(_ column: PodTableColumn) {
        if sort == column { ascending.toggle() }
        else { sort = column; ascending = true }
    }

    private func width(_ column: PodTableColumn) -> CGFloat {
        switch column {
        case .name: 190
        case .age: 75
        case .replicas: 165
        case .deployment: 145
        case .namespace, .node: 110
        case .status: 145
        case .restarts: 75
        }
    }

    private func value(_ column: PodTableColumn, pod: OperationsResource) -> String {
        let deployment = resources.first {
            $0.kind == .deployments && ($0.id == pod.deploymentID || pod.relatedIDs.contains($0.id))
        }
        switch column {
        case .name: return pod.name
        case .age:
            guard let created = pod.createdAt else { return "—" }
            let seconds = max(0, Int(observedAt.timeIntervalSince(created)))
            if seconds >= 86_400 { return "\(seconds / 86_400)d \((seconds % 86_400) / 3_600)h" }
            if seconds >= 3_600 { return "\(seconds / 3_600)h \((seconds % 3_600) / 60)m" }
            if seconds >= 60 { return "\(seconds / 60)m" }
            return "\(seconds)s"
        case .replicas:
            guard let deployment, let desired = deployment.desired else { return "—" }
            return "\(deployment.ready.map(String.init) ?? "—") / \(desired)"
        case .deployment: return deployment?.name ?? "—"
        case .namespace: return pod.namespace ?? "—"
        case .status: return pod.status
        case .restarts: return pod.restarts.map(String.init) ?? "—"
        case .node: return pod.node ?? "—"
        }
    }
}
