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
        ZStack {
            Color("MainColor")
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

                    XMBWaveAnimation()
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
                        .background(Color("LoginEntryBox").opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                        .background(Color("LoginEntryBox").opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .tint(.white)
                }
                .padding(.horizontal, 12)

                HStack(spacing: 12) {
                    Button {
                        // Connect credential validation here before shipping.
                        onAuthenticated()
                    } label: {
                        Text("Login")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color("ButtonColor"))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button(action: authenticateWithFaceID) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color("ButtonColor"))

                            if isAuthenticating {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: isFaceIDAuthenticated ? "checkmark" : "faceid")
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 48, height: 48)
                    }
                    .buttonStyle(.plain)
                    .disabled(isAuthenticating)
                    .accessibilityLabel("Login with Face ID")
                }
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: 360)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(y: -24)
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
