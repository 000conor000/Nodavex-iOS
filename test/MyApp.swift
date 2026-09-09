import SwiftUI

@main struct NodavexApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

private struct AppRootView: View {
    @State private var isAuthenticated = false

    var body: some View {
        ZStack {
            LandingView()

            if !isAuthenticated {
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
