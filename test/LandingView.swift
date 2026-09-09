import SwiftUI

struct LandingView: View {
    private enum LandingTab: String, CaseIterable, Identifiable {
        case home = "Home"
        case activity = "Activity"
        case profile = "Profile"

        var id: Self { self }

        var icon: String {
            switch self {
            case .home:
                return "house.fill"
            case .activity:
                return "chart.bar.fill"
            case .profile:
                return "person.fill"
            }
        }
    }

    @State private var selectedTab: LandingTab = .home

    private var appName: String {
        let bundle = Bundle.main
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "nodavex"
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            page(for: .home)
                .tabItem {
                    Label(LandingTab.home.rawValue, systemImage: LandingTab.home.icon)
                }
                .tag(LandingTab.home)

            page(for: .activity)
                .tabItem {
                    Label(LandingTab.activity.rawValue, systemImage: LandingTab.activity.icon)
                }
                .tag(LandingTab.activity)

            page(for: .profile)
                .tabItem {
                    Label(LandingTab.profile.rawValue, systemImage: LandingTab.profile.icon)
                }
                .tag(LandingTab.profile)
        }
        .tint(Color("ButtonColor"))
    }

    private func page(for tab: LandingTab) -> some View {
        ZStack {
            Color("Background")
                .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Text(appName)
                        .font(.title2.weight(.semibold))

                    Spacer()

                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color("ButtonColor"))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                Spacer()

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

                Spacer()
            }
        }
    }

    private func message(for tab: LandingTab) -> String {
        switch tab {
        case .home:
            return "Welcome back. You’re signed in."
        case .activity:
            return "Your recent activity will appear here."
        case .profile:
            return "Manage your account and preferences."
        }
    }
}

#Preview {
    LandingView()
}
