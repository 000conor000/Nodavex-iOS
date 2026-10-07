import SwiftUI
import UIKit

struct LandingView: View {
    private enum Page: String {
        case home = "Home"
        case notifications = "Notifications"
        case actions = "Actions"
        case settings = "Settings"
    }

    private enum Widget: String, CaseIterable, Identifiable {
        case disk, system, network, notifications
        var id: String { rawValue }
        var dragIdentifier: String { "nodavex.widget." + rawValue }
    }

    @AppStorage("homeWidgetOrder") private var savedWidgetOrder = "disk,system,network,notifications"
    @State private var selectedPage: Page = .home
    @AppStorage("serverProfiles") private var savedProfiles = "[]"
    @State private var settingsSubtitle = "Settings"
    @State private var homeIsScrolling = false
    @State private var homeMenuFrame: CGRect = .zero
    @State private var homeScrollMetrics: [CGFloat] = [0, 0, 0]

    private var homeServers: [ServerProfile] {
        ((try? JSONDecoder().decode([ServerProfile].self, from: Data(savedProfiles.utf8))) ?? [])
            .filter { $0.enabled ?? true }
    }

    private func enabledWidgets(for server: ServerProfile) -> [Widget] {
        widgetOrder.filter { widget in
            switch widget {
            case .disk: return server.disk
            case .system: return server.cpuMemory
            case .network: return server.network
            case .notifications: return server.notifications
            }
        }
    }

    private var widgetOrder: [Widget] {
        var result: [Widget] = []
        for value in savedWidgetOrder.split(separator: ",") {
            if let widget = Widget(rawValue: String(value)), !result.contains(widget) {
                result.append(widget)
            }
        }
        return result + Widget.allCases.filter { !result.contains($0) }
    }

    private func move(_ source: Widget, to target: Widget) -> Bool {
        var order = widgetOrder
        guard source != target,
              let sourceIndex = order.firstIndex(of: source),
              let targetIndex = order.firstIndex(of: target) else { return false }
        order.remove(at: sourceIndex)
        order.insert(source, at: targetIndex)
        withAnimation(.easeInOut(duration: 0.2)) {
            savedWidgetOrder = order.map(\.rawValue).joined(separator: ",")
        }
        return true
    }

    @ViewBuilder
    private func widgetView(_ widget: Widget) -> some View {
        switch widget {
        case .disk:
            DiskSpaceWidget(usage: 0.64)
        case .system:
            SystemUsageWidget(cpuUsage: 0.32, memoryUsage: 0.58)
        case .network:
            NetworkTrafficWidget(uploadRate: 2.4, downloadRate: 18.6)
        case .notifications:
            NotificationCountWidget(info: 2, low: 1, medium: 1, large: 1)
        }
    }

    var body: some View {
        TabView(selection: $selectedPage) {
            Tab("Home", systemImage: "house.fill", value: Page.home) {
                page(.home)
            }
            Tab("Notifications", systemImage: "bell", value: Page.notifications) {
                page(.notifications)
            }
            Tab("Actions", systemImage: "bolt", value: Page.actions) {
                page(.actions)
            }
            Tab("Settings", systemImage: "gearshape", value: Page.settings) {
                page(.settings)
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
    }

    private func page(_ page: Page) -> some View {
        GeometryReader { geometry in
        ZStack {
            VStack(spacing: 24) {
                if page == .home {
                    NodavexPageHeader(
                        pageTitle: page == .settings ? settingsSubtitle : page.rawValue,
                        titleOffset: (geometry.safeAreaInsets.trailing - geometry.safeAreaInsets.leading) / 2,
                        dividerTrailingExtension: max(0, geometry.safeAreaInsets.trailing - geometry.safeAreaInsets.leading)
                    )
                }

                if page == .home {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                        if homeServers.isEmpty {
                            Text("Add a server in Settings to display its widgets")
                                .font(.subheadline)
                                .foregroundStyle(Color(white: 0.4))
                        }
                        ForEach(homeServers) { server in
                        VStack(alignment: .leading, spacing: 12) {
                        Text(server.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color(white: 0.65))
                        let widgets = enabledWidgets(for: server)
                        let columnCount = max(1, Int((geometry.size.width - 48 + 16) / 176))
                        let rowCount = (widgets.count + columnCount - 1) / columnCount
                        VStack(spacing: 16) {
                            ForEach(0..<rowCount, id: \.self) { row in
                                AdaptiveHomeWidgetRow(
                                    baseWidth: max(1, geometry.size.width - 48),
                                    sidebarWidth: max(0, geometry.safeAreaInsets.trailing - geometry.safeAreaInsets.leading),
                                    menuFrame: homeMenuFrame,
                                    viewportHeight: homeScrollMetrics[2] > 0 ? homeScrollMetrics[2] : max(0, geometry.size.height - 160)
                                ) {
                                HStack(spacing: 16) {
                                    ForEach(Array(widgets.dropFirst(row * columnCount).prefix(columnCount))) { widget in
                                widgetView(widget)
                                    .draggable(widget.dragIdentifier)
                                    .dropDestination(for: String.self) { items, _ in
                                        guard items.count == 1,
                                              let source = Widget.allCases.first(where: {
                                                  $0.dragIdentifier == items[0]
                                              }) else { return false }
                                        return move(source, to: widget)
                                    }
                                    .accessibilityHint("Drag to reorder. Actions can also move this widget.")
                                    .accessibilityAction(named: "Move earlier") {
                                        let order = widgetOrder
                                        if let index = order.firstIndex(of: widget), index > 0 {
                                            _ = move(widget, to: order[index - 1])
                                        }
                                    }
                                    .accessibilityAction(named: "Move later") {
                                        let order = widgetOrder
                                        if let index = order.firstIndex(of: widget), index < order.count - 1 {
                                            _ = move(widget, to: order[index + 1])
                                        }
                                    }
                                    }
                                }
                                }
                            }
                        }
                        }
                        }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .onScrollPhaseChange { _, phase in
                        withAnimation(.easeOut(duration: phase == .idle ? 0.35 : 0.1)) {
                            homeIsScrolling = phase != .idle
                        }
                    }
                    .background(HomeMenuFrameReader { frame in
                        if homeMenuFrame != frame { homeMenuFrame = frame }
                    })
                    .onScrollGeometryChange(for: [CGFloat].self) { scroll in
                        [scroll.contentOffset.y + scroll.contentInsets.top,
                         scroll.contentSize.height + scroll.contentInsets.top + scroll.contentInsets.bottom,
                         scroll.containerSize.height]
                    } action: { _, metrics in
                        homeScrollMetrics = metrics
                    }
                    .scrollClipDisabled()
                    .clipShape(HomeWidgetViewportClip(
                        trailingExtension: max(0, geometry.safeAreaInsets.trailing - geometry.safeAreaInsets.leading)
                    ))
                    .overlay(alignment: .leading) {
                        GeometryReader { viewport in
                            let contentHeight = homeScrollMetrics[1]
                            let visibleHeight = homeScrollMetrics[2]
                            if contentHeight > visibleHeight, visibleHeight > 0 {
                                let trackHeight = max(0, viewport.size.height - 8)
                                let thumbHeight = min(trackHeight, max(28, trackHeight * visibleHeight / contentHeight))
                                let fraction = min(1, max(0, homeScrollMetrics[0] / (contentHeight - visibleHeight)))
                                Capsule()
                                    .fill(Color.white.opacity(0.35))
                                    .frame(width: 3, height: thumbHeight)
                                    .offset(x: -10, y: 4 + fraction * (trackHeight - thumbHeight))
                            }
                        }
                        .opacity(homeIsScrolling ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                } else if page == .notifications {
                    NotificationsInboxView(
                        isPortrait: geometry.size.height > geometry.size.width,
                        hasSideInset: max(geometry.safeAreaInsets.leading, geometry.safeAreaInsets.trailing) > 40,
                        titleOffset: (geometry.safeAreaInsets.trailing - geometry.safeAreaInsets.leading) / 2
                    )
                } else if page == .actions {
                    VStack(spacing: 6) {
                        NodavexPageHeader(
                            pageTitle: "Actions",
                            titleOffset: (geometry.safeAreaInsets.trailing - geometry.safeAreaInsets.leading) / 2,
                            dividerTrailingExtension: max(0, geometry.safeAreaInsets.trailing - geometry.safeAreaInsets.leading)
                        )
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    ServerSettingsView(
                        subtitle: $settingsSubtitle,
                        titleOffset: (geometry.safeAreaInsets.trailing - geometry.safeAreaInsets.leading) / 2,
                        dividerTrailingExtension: max(0, geometry.safeAreaInsets.trailing - geometry.safeAreaInsets.leading)
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .ignoresSafeArea(.container, edges: .top)
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        .background(Color.black.ignoresSafeArea())
        }
    }
}

// Keep card layouts at full width and let their trailing edges follow the menu.
private struct AdaptiveHomeWidgetRow<Content: View>: View {
    let baseWidth: CGFloat
    let sidebarWidth: CGFloat
    let menuFrame: CGRect
    let viewportHeight: CGFloat
    @ViewBuilder var content: () -> Content

    private var exclusion: CGRect {
        guard sidebarWidth > 0 else { return .null }
        let compact = !menuFrame.isEmpty && menuFrame.width < 160
            && menuFrame.height < 340 && menuFrame.minY >= 0
        let menu = compact ? menuFrame
            : CGRect(x: baseWidth + 12, y: viewportHeight - 224,
                     width: sidebarWidth, height: 248)
        return menu.insetBy(dx: -10, dy: -8)
    }

    var body: some View {
        content()
            .environment(\.homeMenuExclusion, exclusion)
            .frame(width: baseWidth + sidebarWidth, alignment: .leading)
            .frame(width: baseWidth, alignment: .leading)
    }
}

private struct HomeMenuExclusionKey: EnvironmentKey {
    static let defaultValue: CGRect = .null
}

private extension EnvironmentValues {
    var homeMenuExclusion: CGRect {
        get { self[HomeMenuExclusionKey.self] }
        set { self[HomeMenuExclusionKey.self] = newValue }
    }
}

private struct MenuContourCard: ViewModifier {
    @Environment(\.homeMenuExclusion) private var menu
    @State private var frame: CGRect = .zero

    private var contour: MenuContourShape {
        MenuContourShape(menuTop: menu.minY - frame.minY,
                         menuBottom: menu.maxY - frame.minY,
                         menuRadius: menu.isNull ? 0 : min(menu.width, menu.height) / 2,
                         intrusion: menu.isNull ? 0 : max(0, frame.maxX - menu.minX))
    }

    func body(content: Content) -> some View {
        let shape = contour
        // Reflow content using the deepest part of the rounded cutout in this card.
        let nearestY = min(frame.height, max(0, (shape.menuTop + shape.menuBottom) / 2))
        let inset = min(max(0, frame.width - 120), shape.inset(at: nearestY))
        content
            .padding(.trailing, inset)
            .background { shape.fill(Color.white.opacity(0.045)) }
            .overlay { shape.stroke(Color.white.opacity(0.1), lineWidth: 1) }
            .clipShape(shape)
            .contentShape(shape)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .scrollView)
            } action: { frame = $0 }
    }
}

private struct MenuContourShape: Shape {
    var menuTop: CGFloat
    var menuBottom: CGFloat
    var menuRadius: CGFloat
    var intrusion: CGFloat

    func inset(at y: CGFloat) -> CGFloat {
        guard intrusion > 0 else { return 0 }
        let radius = max(1, min(menuRadius, intrusion))
        let depth = min(y - menuTop, menuBottom - y)
        let lead: CGFloat = 18
        let rounding = min(4, radius / 2)
        let capStart = sqrt(max(0, radius * radius - pow(radius - rounding, 2)))
        let startInset = intrusion - radius + capStart
        if depth < 0 {
            let t = min(1, max(0, (depth + lead) / lead))
            let slope = (radius - rounding) / max(1, capStart)
            // Match the tangent of the capsule cap with a short curved shoulder.
            return max(0, (3 * t * t - 2 * t * t * t) * startInset
                       + (t * t * t - t * t) * lead * slope)
        }
        let capDepth = min(radius, depth + rounding)
        return intrusion - radius + sqrt(max(0, radius * radius - pow(radius - capDepth, 2)))
    }

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = min(18, rect.height / 2)
        func edge(_ y: CGFloat) -> CGFloat {
            guard intrusion > 0 else { return rect.maxX }
            return rect.maxX - min(max(0, rect.width - 120), inset(at: y))
        }
        var path = Path()
        path.move(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: edge(0) - radius, y: 0))
        // Deform the corner arcs and side together, preserving their tangents.
        // Cubic segments avoid the kink produced by joining a separate corner
        // to a moving side at a different angle.
        let arc = radius * .pi / 2
        let straight = max(0, rect.height - 2 * radius)
        let length = arc * 2 + straight
        func point(_ position: CGFloat) -> CGPoint {
            let u = min(length, max(0, position))
            let x: CGFloat
            let y: CGFloat
            if u < arc {
                let angle = u / radius
                x = rect.width - radius + radius * sin(angle)
                y = radius - radius * cos(angle)
            } else if u <= arc + straight {
                x = rect.width
                y = radius + u - arc
            } else {
                let angle = (u - arc - straight) / radius
                x = rect.width - radius + radius * cos(angle)
                y = rect.height - radius + radius * sin(angle)
            }
            return CGPoint(x: x - (rect.maxX - edge(y)), y: y)
        }
        func tangent(_ u: CGFloat) -> CGPoint {
            let low = max(0, u - 0.01)
            let high = min(length, u + 0.01)
            let p = point(low), q = point(high)
            return CGPoint(x: (q.x - p.x) / (high - low), y: (q.y - p.y) / (high - low))
        }
        var u: CGFloat = 0
        while u < length {
            let next = min(length, u + 2)
            let p = point(u), q = point(next)
            let start = tangent(u), end = tangent(next)
            let step = (next - u) / 3
            path.addCurve(to: q,
                          control1: CGPoint(x: p.x + start.x * step, y: p.y + start.y * step),
                          control2: CGPoint(x: q.x - end.x * step, y: q.y - end.y * step))
            u = next
        }
        path.addLine(to: CGPoint(x: radius, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.height - radius),
                          control: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero)
        path.closeSubpath()
        return path
    }
}

// Measure the native menu rather than reserving an arbitrary tall region.
private struct HomeMenuFrameReader: UIViewRepresentable {
    let onFrame: (CGRect) -> Void

    func makeUIView(context: Context) -> MenuProbe {
        let view = MenuProbe()
        view.onFrame = onFrame
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: MenuProbe, context: Context) {
        view.onFrame = onFrame
        view.setNeedsLayout()
    }

    final class MenuProbe: UIView {
        var onFrame: ((CGRect) -> Void)?

        override func layoutSubviews() {
            super.layoutSubviews()
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                func findMenu(_ view: UIView) -> UITabBar? {
                    if let bar = view as? UITabBar, !bar.isHidden, bar.alpha > 0 { return bar }
                    return view.subviews.lazy.compactMap { findMenu($0) }.first
                }
                guard let bar = findMenu(window) else { return }
                func controlFrames(_ view: UIView) -> [CGRect] {
                    guard !view.isHidden, view.alpha > 0 else { return [] }
                    let children = view.subviews.flatMap { controlFrames($0) }
                    if !children.isEmpty { return children }
                    if view is UIControl, view.bounds.width < 160, view.bounds.height < 120 {
                        return [view.convert(view.bounds, to: self)]
                    }
                    return []
                }
                let frames = controlFrames(bar).filter { !$0.isEmpty }
                let frame = frames.reduce(CGRect.null) { $0.union($1) }
                self.onFrame?(frame.isNull ? bar.convert(bar.bounds, to: self) : frame)
            }
        }
    }
}

// Keep the scroll viewport's vertical boundaries while allowing cards to
// occupy the unused right sidebar space above the native menu.
private struct HomeWidgetViewportClip: Shape {
    var trailingExtension: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY,
                    width: rect.width + trailingExtension, height: rect.height))
    }
}

struct NodavexPageHeader: View {
    @AppStorage("metricColoursEnabled") private var metricColoursEnabled = false
    let pageTitle: String
    let titleOffset: CGFloat
    var dividerTrailingExtension: CGFloat = 0
    var actions: AnyView? = nil
    var backAction: (() -> Void)? = nil

    private var appName: String {
        let bundle = Bundle.main
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "nodavex"
    }

    var body: some View {
        VStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { metricColoursEnabled.toggle() }
            } label: {
            ZStack {
                Text(appName)
                    .font(.system(size: 34, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)

                XMBWaveAnimation()
                    .frame(width: 280, height: 120)
                    .scaleEffect(0.7)
                    .frame(width: 196, height: 84)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Metric colours")
            .accessibilityValue(metricColoursEnabled ? "On" : "Off")
            .accessibilityHint("Toggle colours for metric values and notification urgency")
            .offset(x: titleOffset, y: -8)

            HStack(spacing: 12) {
                Text(pageTitle)
                    .font(.system(size: 22, weight: .light, design: .rounded))
                    .foregroundStyle(Color(white: 0.65))
                    .accessibilityAddTraits(.isHeader)
                    .id(pageTitle)
                    .transition(.opacity)
                Spacer(minLength: 0)
                if let actions { actions }
            }
            .padding(.top, 6)
            .animation(.easeInOut(duration: 0.25), value: pageTitle)

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.trailing, -dividerTrailingExtension)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topLeading) {
            if let backAction {
                Button(action: backAction) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .scaleEffect(0.8, anchor: .topLeading)
                .accessibilityLabel("Back")
            }
        }
    }
}

#Preview {
    LandingView()
}

private struct DiskSpaceWidget: View {
    @AppStorage("metricColoursEnabled") private var metricColoursEnabled = false
    let usage: Double

    private var fraction: Double { min(max(usage, 0), 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Disk Space", systemImage: "internaldrive")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(white: 0.85))

                Spacer()


            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 24, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(metricColoursEnabled ? MetricPalette.usage(fraction) : Color(white: 0.85))

                Text("used")
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.5))
            }

            VStack(spacing: 5) {
                ProgressView(value: fraction, total: 1)
                    .tint(metricColoursEnabled ? MetricPalette.usage(fraction) : Color(white: 0.7))
                    .accessibilityLabel("Disk space used")
                    .accessibilityValue(Text(fraction, format: .percent))

                HStack {
                    Text("0%")
                    Spacer()
                    Text("100%")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color(white: 0.5))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 128, alignment: .topLeading)
        .modifier(MenuContourCard())
    }
}

private struct SystemUsageWidget: View {
    let cpuUsage: Double
    let memoryUsage: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CPU & Memory")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(white: 0.85))
                Spacer()

            }

            HStack(spacing: 14) {
                UsageDonut(title: "CPU", usage: cpuUsage)
                UsageDonut(title: "Memory", usage: memoryUsage)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 128, alignment: .topLeading)
        .modifier(MenuContourCard())
    }
}

private struct UsageDonut: View {
    @AppStorage("metricColoursEnabled") private var metricColoursEnabled = false
    let title: String
    let usage: Double

    private var fraction: Double { min(max(usage, 0), 1) }

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(metricColoursEnabled ? MetricPalette.usage(fraction) : Color(white: 0.7), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(metricColoursEnabled ? MetricPalette.usage(fraction) : Color(white: 0.85))
            }
            .frame(width: 54, height: 54)

            Text(title)
                .font(.caption2)
                .foregroundStyle(Color(white: 0.5))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) usage")
        .accessibilityValue(Text(fraction, format: .percent))
    }
}

private struct NetworkTrafficWidget: View {
    @AppStorage("metricColoursEnabled") private var metricColoursEnabled = false
    // Placeholder rates in megabits per second until a data source is connected.
    let uploadRate: Double
    let downloadRate: Double
    // Demonstration capacity until the server supplies its link speed.
    private let linkCapacityMbps: Double = 100

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Network Traffic", systemImage: "network")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color(white: 0.85))

            trafficRow("Upload", symbol: "arrow.up", rate: uploadRate)
            trafficRow("Download", symbol: "arrow.down", rate: downloadRate)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 128, alignment: .topLeading)
        .modifier(MenuContourCard())
    }

    private func trafficRow(_ title: String, symbol: String, rate: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(metricColoursEnabled ? MetricPalette.usage(rate / linkCapacityMbps) : Color(white: 0.7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(Color(white: 0.5))
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(rate, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 18, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(metricColoursEnabled ? MetricPalette.usage(rate / linkCapacityMbps) : Color(white: 0.85))
                    Text("Mbps")
                        .font(.caption2)
                        .foregroundStyle(Color(white: 0.5))
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(rate.formatted(.number.precision(.fractionLength(1)))) megabits per second")
    }
}

private struct NotificationCountWidget: View {
    @AppStorage("metricColoursEnabled") private var metricColoursEnabled = false
    let info: Int
    let low: Int
    let medium: Int
    let large: Int

    private var total: Int {
        max(info, 0) + max(low, 0) + max(medium, 0) + max(large, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notifications", systemImage: "bell")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color(white: 0.85))

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(total, format: .number)
                        .font(.system(size: 36, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(metricColoursEnabled ? MetricPalette.urgency(large > 0 ? "High" : medium > 0 ? "Medium" : low > 0 ? "Low" : "Info") : Color(white: 0.85))

                    Text(total > 0 ? "Unread" : "All caught up")
                        .font(.caption2)
                        .foregroundStyle(Color(white: 0.5))
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 4) {
                    metric("Info", count: info)
                    metric("Low", count: low)
                    metric("Medium", count: medium)
                    metric("Large", count: large)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 128, alignment: .topLeading)
        .modifier(MenuContourCard())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Notifications")
        .accessibilityValue("\(total) unread: \(max(info, 0)) info, \(max(low, 0)) low, \(max(medium, 0)) medium, \(max(large, 0)) large")
    }

    private func metric(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(Color(white: 0.45))
            Spacer(minLength: 0)
            Text(max(count, 0), format: .number)
                .monospacedDigit()
                .foregroundStyle(metricColoursEnabled && count > 0 ? MetricPalette.urgency(title) : Color(white: 0.65))
        }
        .font(.system(size: 10))
        .frame(width: 68)
    }
}

// Shared thresholds keep gauges, values, and notifications consistent.
enum MetricPalette {
    static func usage(_ fraction: Double) -> Color {
        if fraction >= 0.90 { return .red }
        if fraction >= 0.75 { return .orange }
        return .green
    }

    static func urgency(_ title: String) -> Color {
        switch title {
        case "Critical", "High", "Large": return .red
        case "Medium": return .orange
        case "Low": return .green
        default: return .cyan
        }
    }
}
