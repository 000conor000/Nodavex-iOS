import SwiftUI
import LocalAuthentication

struct LoginView: View {
    var onAuthenticated: () -> Void = {}

    @State private var username = ""
    @State private var password = ""
    @State private var isAuthenticating = false
    @State private var isFaceIDAuthenticated = false
    @State private var authenticationError: String?

    private var appName: String {
        let bundle = Bundle.main

        if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !displayName.isEmpty {
            return displayName
        }

        if let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
           !bundleName.isEmpty {
            return bundleName
        }

        return "App"
    }

    private func authenticateWithFaceID() {
        guard !isAuthenticating else { return }

        let context = LAContext()
        context.localizedCancelTitle = "Use Password"

        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError),
              context.biometryType == .faceID else {
            authenticationError = policyError?.localizedDescription
                ?? "Face ID is not available or has not been set up on this device."
            return
        }

        isAuthenticating = true

        Task {
            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: "Log in to your account"
                )

                isAuthenticating = false

                if success {
                    isFaceIDAuthenticated = true
                    onAuthenticated()
                }
            } catch {
                isAuthenticating = false
                authenticationError = error.localizedDescription
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Text(appName)
                        .font(.system(size: 60, weight: .thin, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)

                    // Original animation retained for reverting this SVG test:
                    // XMBWaveAnimation()
                    AnimatedRibbonLogo()
                        .frame(width: 200, height: 200)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(-1)

                }
                    .frame(maxWidth: .infinity)
                    .frame(height: 120)
                    .offset(y: -36)

                VStack(spacing: 16) {
                    TextField(
                        "Username",
                        text: $username,
                        prompt: Text("Username").foregroundStyle(.white.opacity(0.7))
                    )
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.white.opacity(0.25))
                                .frame(height: 1)
                        }
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .tint(.white)

                    SecureField(
                        "Password",
                        text: $password,
                        prompt: Text("Password").foregroundStyle(.white.opacity(0.7))
                    )
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.white.opacity(0.25))
                                .frame(height: 1)
                        }
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .tint(.white)
                }
                .frame(maxWidth: 280)
                .padding(.horizontal, 12)
                .padding(.bottom, 34)

                HStack(spacing: 12) {
                    Button {
                        // Connect credential validation here before shipping.
                        onAuthenticated()
                    } label: {
                        Text("Login")
                            .fontWeight(.semibold)
                            .foregroundStyle(Color(white: 0.6))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background {
                                Capsule()
                                    .fill(Color(white: 0.75).opacity(0.075))
                            }
                            .overlay {
                                Capsule()
                                    .strokeBorder(Color(white: 0.75).opacity(0.35), lineWidth: 1)
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: authenticateWithFaceID) {
                        ZStack {
                            Circle()
                                .fill(Color(white: 0.75).opacity(0.075))
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color(white: 0.75).opacity(0.35), lineWidth: 1)
                                }

                            if isAuthenticating {
                                ProgressView()
                                    .tint(Color(white: 0.6))
                            } else {
                                Image(systemName: isFaceIDAuthenticated ? "checkmark" : "faceid")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundStyle(Color(white: 0.6))
                            }
                        }
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isAuthenticating)
                    .accessibilityLabel("Login with Face ID")
                }
                .frame(maxWidth: 280)
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(x: (geometry.safeAreaInsets.trailing - geometry.safeAreaInsets.leading) / 2, y: -24)
        }
        }
        .alert(
            "Face ID",
            isPresented: Binding(
                get: { authenticationError != nil },
                set: { if !$0 { authenticationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                authenticationError = nil
            }
        } message: {
            Text(authenticationError ?? "Face ID authentication failed.")
        }
    }
}

#Preview {
    LoginView()
}
