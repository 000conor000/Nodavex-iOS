import SwiftUI
import UIKit
import OSLog

@main struct NodavexApp: App {
    init() {
        do {
            try ServerProfile.installKubernetesSample()
        } catch {
            Logger(subsystem: "com.conorsokellpersonalteam.nodavex", category: "SampleAgent")
                .error("Could not add the Kubernetes sample agent: \(error.localizedDescription, privacy: .public)")
        }
        UITabBar.appearance().unselectedItemTintColor = UIColor(white: 0.45, alpha: 1)
        UITabBar.appearance().tintColor = .white
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .statusBarHidden(true)
        }
    }
}

private struct AppRootView: View {
    @State private var isAuthenticated = false
    private var notificationBadge = NotificationBadgeState()

    var body: some View {
        ZStack {
            if isAuthenticated {
                LandingView()
                    .transition(.opacity)
            } else {
                LoginView {
                    withAnimation(.easeInOut(duration: 0.7)) {
                        isAuthenticated = true
                    }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .modifier(NotificationIconBadgeModifier(count: notificationBadge.unreadCount,
                                              requestPermission: isAuthenticated))
    }
}
