import SwiftUI
import RealityKit
// import RealityKitContent // Uncomment if you have a RealityKitContent bundle

struct LoginView: View {
    @State private var username: String = ""
    @State private var password: String = ""

    var body: some View {
        VStack {
            // RealityKit spinning earth mesh
            RealityView { content in
                if let earth = try? await ModelEntity(named: "Earth", in: realityKitContentBundle) {
                    earth.setOrientation(simd_quatf(angle: .pi/2, axis: [1,0,0]), relativeTo: nil)
                    content.add(earth)
                }
            } update: { content in
                let rotation = simd_quatf(angle: Float(Date().timeIntervalSinceReferenceDate).truncatingRemainder(dividingBy: .pi * 2), axis: [0,1,0])
                content.entities.first?.setOrientation(rotation, relativeTo: nil)
            }
            .frame(width: 120, height: 120)
            .padding(.bottom, 8)
            // Fallback if RealityKitContent/Earth model unavailable:
            // Circle().fill(Color.blue).frame(width: 120, height: 120).rotationEffect(.degrees(Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 360)))
            //     .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: Date().timeIntervalSinceReferenceDate)
            //     .padding(.bottom, 8)

            Text("Login")
                .font(.largeTitle)
                .bold()
                .padding(.bottom, 16)

            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.gray, lineWidth: 1)
                    TextField("Username", text: $username)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 48)

                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.gray, lineWidth: 1)
                    SecureField("Password", text: $password)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 48)
            }
            .padding(.horizontal, 32)

            Button(action: {
                // Handle login
            }) {
                Text("Sign In")
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .edgesIgnoringSafeArea(.all)
    }
}
