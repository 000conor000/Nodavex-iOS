import SwiftUI

struct KubernetesMetricWidget: View {
    let kind: KubernetesWidgetKind
    let metrics: KubernetesMetrics?
    var isDemo = true
    @AppStorage("metricColoursEnabled") private var metricColoursEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(kind.title, systemImage: kind.symbol)
                .symbolRenderingMode(.monochrome)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color(white: 0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            VStack(spacing: 4) { rows }
            Spacer(minLength: 0)
            Text(metrics == nil ? "Kubernetes · Unavailable" : isDemo ? "Kubernetes · Demo data" : "Kubernetes")
                .font(.caption2)
                .foregroundStyle(Color(white: 0.4))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 128, alignment: .topLeading)
        .modifier(MenuContourCard())
    }

    @ViewBuilder private var rows: some View {
        switch kind {
        case .nodes:
            row("Ready", ratio(metrics?.nodes?.ready, metrics?.nodes?.total))
            row("Not ready", number(metrics?.nodes?.notReady), attention: positive(metrics?.nodes?.notReady))
            row("Under pressure", number(metrics?.nodes?.pressure), attention: positive(metrics?.nodes?.pressure))
        case .pods:
            row("Running", number(metrics?.pods?.running))
            row("Pending", number(metrics?.pods?.pending), attention: positive(metrics?.pods?.pending))
            row("Failed", number(metrics?.pods?.failed), attention: positive(metrics?.pods?.failed))
        case .workloads:
            row("Deployments", ratio(metrics?.workloads?.availableDeployments, metrics?.workloads?.deployments))
            row("Replicas", ratio(metrics?.workloads?.readyReplicas, metrics?.workloads?.desiredReplicas))
            row("DaemonSet pods", ratio(metrics?.workloads?.readyDaemonSetPods, metrics?.workloads?.desiredDaemonSetPods))
        case .resources:
            row("CPU cores", resourceRatio(metrics?.resources?.cpuUsedCores, metrics?.resources?.cpuAllocatableCores))
            row("Memory GiB", resourceRatio(metrics?.resources?.memoryUsedBytes, metrics?.resources?.memoryAllocatableBytes, divisor: 1_073_741_824))
            row("Requested CPU", decimal(metrics?.resources?.cpuRequestedCores))
        case .restarts:
            row(windowLabel(metrics?.restarts?.windowSeconds, fallback: "Restarts"), number(metrics?.restarts?.total), attention: positive(metrics?.restarts?.total))
            row("CrashLoopBackOff", number(metrics?.restarts?.crashLooping), attention: positive(metrics?.restarts?.crashLooping))
            row("Last OOMKilled", number(metrics?.restarts?.oomKilled), attention: positive(metrics?.restarts?.oomKilled))
        case .storage:
            row("Bound PVCs", number(metrics?.storage?.boundClaims))
            row("Pending PVCs", number(metrics?.storage?.pendingClaims), attention: positive(metrics?.storage?.pendingClaims))
            row("Used / total GiB", resourceRatio(metrics?.storage?.usedBytes, metrics?.storage?.capacityBytes, divisor: 1_073_741_824))
        case .jobs:
            row("Active", number(metrics?.jobs?.active))
            row("Failed", number(metrics?.jobs?.failed), attention: positive(metrics?.jobs?.failed))
            row("Succeeded", number(metrics?.jobs?.succeeded))
        case .events:
            row(windowLabel(metrics?.events?.windowSeconds, fallback: "Warnings"), number(metrics?.events?.warnings), attention: positive(metrics?.events?.warnings))
            row("Scheduling", number(metrics?.events?.schedulingFailures), attention: positive(metrics?.events?.schedulingFailures))
            row("Image pulls", number(metrics?.events?.imagePullFailures), attention: positive(metrics?.events?.imagePullFailures))
        }
    }

    private func row(_ title: String, _ value: String, attention: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(title).foregroundStyle(Color(white: 0.5))
            Spacer(minLength: 2)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(metricColoursEnabled && attention ? .orange : Color(white: 0.85))
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }

    private func number(_ value: Int?) -> String {
        guard let value, value >= 0 else { return "—" }
        return value.formatted()
    }
    private func positive(_ value: Int?) -> Bool { (value ?? 0) > 0 }
    private func ratio(_ value: Int?, _ total: Int?) -> String { "\(number(value)) / \(number(total))" }
    private func decimal(_ value: Double?) -> String {
        guard let value, value.isFinite, value >= 0 else { return "—" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
    private func resourceRatio(_ value: Double?, _ total: Double?, divisor: Double = 1) -> String {
        "\(decimal(value.map { $0 / divisor })) / \(decimal(total.map { $0 / divisor }))"
    }
    private func windowLabel(_ seconds: Int?, fallback: String) -> String {
        guard let seconds, seconds > 0 else { return fallback }
        return seconds % 3_600 == 0 ? "Last \(seconds / 3_600)h" : "Last \(seconds)s"
    }
}
