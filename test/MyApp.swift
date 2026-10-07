import SwiftUI
import UIKit

@main struct NodavexApp: App {
    init() {
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
    }
}
