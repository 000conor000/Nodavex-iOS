import SwiftUI

struct LoginView: View {
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            Color("MainColor")
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Login")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(Color("MainColor"))

                VStack(spacing: 16) {
                    ZStack {
                        Color("LoginEntryBox").opacity(0.3)
                            .cornerRadius(8)
                        TextField("Username", text: $username)
                            .padding(10)
                            .textFieldStyle(.plain)
                            .accentColor(Color("MainColor"))
                    }

                    ZStack {
                        Color("LoginEntryBox").opacity(0.3)
                            .cornerRadius(8)
                        SecureField("Password", text: $password)
                            .padding(10)
                            .textFieldStyle(.plain)
                            .accentColor(Color("MainColor"))
                    }
                }
                .padding()
                .cornerRadius(16)

                Button("Login") {
                    // Handle login action here
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("MainColor"))
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }
}

#Preview {
    LoginView()
}
