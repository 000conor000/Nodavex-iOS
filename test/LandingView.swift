import SwiftUI

struct LandingView: View {
    private enum NetworkTool: String, CaseIterable, Identifiable {
        case whois = "Whois"
        case ping = "Ping"
        case traceRoute = "Trace Route"
        case dnsLookup = "DNS Lookup"
        case ipLookup = "IP Lookup"
        case portChecker = "Port Checker"

        var id: Self { self }

        var icon: String {
            switch self {
            case .whois: return "person.text.rectangle"
            case .ping: return "dot.radiowaves.left.and.right"
            case .traceRoute: return "point.topleft.down.to.point.bottomright.curvepath"
            case .dnsLookup: return "server.rack"
            case .ipLookup: return "location.magnifyingglass"
            case .portChecker: return "door.left.hand.open"
            }
        }

        var detail: String {
            switch self {
            case .portChecker: return "TCP & UDP"
            default: return "Network utility"
            }
        }
    }

    private enum LandingTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case ssh = "SSH"
        case kubernetes = "Kubernetes"
        case notes = "Notes"
        case shell = "Shell"
        case settings = "Settings"

        var id: Self { self }

        var icon: String {
            switch self {
            case .overview:
                return "rectangle.grid.2x2.fill"
            case .ssh:
                return "network"
            case .kubernetes:
                return "shippingbox.fill"
            case .notes:
                return "note.text"
            case .shell:
                return "terminal.fill"
            case .settings:
                return "gearshape.fill"
            }
        }
    }

    @State private var selectedTab: LandingTab = .overview
    @State private var selectedNetworkTool: NetworkTool?
    @State private var showingPingConfiguration = false

    var body: some View {
        TabView(selection: $selectedTab) {
            page(for: .overview).tabItem {
                Label(LandingTab.overview.rawValue, systemImage: LandingTab.overview.icon)
            }.tag(LandingTab.overview)

            page(for: .ssh).tabItem {
                Label(LandingTab.ssh.rawValue, systemImage: LandingTab.ssh.icon)
            }.tag(LandingTab.ssh)
            page(for: .kubernetes).tabItem {
                Label(LandingTab.kubernetes.rawValue, systemImage: LandingTab.kubernetes.icon)
            }.tag(LandingTab.kubernetes)
            page(for: .notes).tabItem {
                Label(LandingTab.notes.rawValue, systemImage: LandingTab.notes.icon)
            }.tag(LandingTab.notes)
            page(for: .shell).tabItem {
                Label(LandingTab.shell.rawValue, systemImage: LandingTab.shell.icon)
            }.tag(LandingTab.shell)
            page(for: .settings).tabItem {
                Label(LandingTab.settings.rawValue, systemImage: LandingTab.settings.icon)
            }.tag(LandingTab.settings)

        }
        .tint(Color("ButtonColor"))
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    private func page(for tab: LandingTab) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color("BackgroundEnd"), Color("BackgroundStart")],
                startPoint: .top,
                endPoint: .bottom
            )
                .ignoresSafeArea()

            VStack(spacing: 24) {
                NodavexHeader(
                    backAction: tab == .overview && selectedNetworkTool != nil ? {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedNetworkTool = nil
                        }
                    } : nil
                )

                Spacer()

                if tab == .overview, let selectedNetworkTool {
                    if selectedNetworkTool == .ping {
                        PingClientView(showingAddConfiguration: $showingPingConfiguration)
                    } else {
                        toolDetail(selectedNetworkTool)
                    }
                } else if tab == .overview {
                    networkTools
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(Color("ButtonColor"))

                        Text(tab.rawValue)
                            .font(.largeTitle.weight(.semibold))

                        Text(message(for: tab))
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                }

                Spacer()
            }
        }
    }

    private var networkTools: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 14
            ) {
                ForEach(NetworkTool.allCases) { tool in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedNetworkTool = tool
                        }
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 25, weight: .semibold))

                            Text(tool.rawValue)
                                .font(.headline)

                            Text(tool.detail)
                                .font(.caption)
                                .opacity(0.72)
                        }
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, minHeight: 112)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func toolDetail(_ tool: NetworkTool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: tool.icon)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color("ButtonColor"))

            Text(tool.rawValue)
                .font(.largeTitle.weight(.semibold))

            Text(tool.detail)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
    }

    private func message(for tab: LandingTab) -> String {
        switch tab {
        case .overview:
            return "Your nodavex overview will appear here."
        case .ssh:
            return "Manage your SSH connections."
        case .kubernetes:
            return "View and manage your Kubernetes resources."
        case .notes:
            return "Keep your notes close at hand."
        case .shell:
            return "Open a shell session."
        case .settings:
            return "Manage app settings and preferences."
        }
    }
}

/// A fixed header shared by root and pushed pages. The optional back button is
/// overlaid independently so it never changes the title or animation position.
struct NodavexHeader: View {
    var backAction: (() -> Void)?

    init(backAction: (() -> Void)? = nil) {
        self.backAction = backAction
    }

    private var appName: String {
        let bundle = Bundle.main
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "nodavex"
    }

    var body: some View {
        ZStack {
            Text(appName)
                .font(.title2.weight(.semibold))

            XMBWaveAnimation(
                primaryColor: Color("ButtonColor"),
                accentColor: Color("MainColor"),
                speed: 1
            )
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .scaleEffect(x: 1, y: 0.62)

            if let backAction {
                HStack {
                    Button(action: backAction) {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .tint(Color("ButtonColor"))
                    .accessibilityLabel("Back")

                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .padding(.horizontal, 24)
        .offset(y: -22)
    }
}

#Preview {
    LandingView()
}
