import SwiftUI

struct LockScreenView: View {
    @ObservedObject var authService: AuthService
    @State private var logoScale: CGFloat = 0.85
    @State private var logoOpacity: CGFloat = 0
    @State private var glowOpacity: CGFloat = 0

    var body: some View {
        ZStack {
            // Background — matches the logo's dark metallic feel
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.10),
                    Color(red: 0.10, green: 0.12, blue: 0.16),
                    Color(red: 0.06, green: 0.07, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo Image from asset catalog
                VStack(spacing: 20) {
                    ZStack {
                        // Glow behind the logo
                        Circle()
                            .fill(NC.teal.opacity(0.15))
                            .frame(width: 200, height: 200)
                            .blur(radius: 40)
                            .opacity(glowOpacity)

                        Image("NodeCompassLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 280)
                    }
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                }

                Spacer()

                // Unlock section
                VStack(spacing: 24) {
                    Button {
                        Task { await authService.authenticate() }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "faceid")
                                .font(.title2)
                            Text("Unlock")
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [NC.teal, NC.teal.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
                        .shadow(color: NC.teal.opacity(0.3), radius: 16, y: 6)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                        Text("All data stored on-device only")
                            .font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 60)
            }
        }
        .task {
            withAnimation(.easeOut(duration: 0.9)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 1.5).delay(0.3)) {
                glowOpacity = 1.0
            }
            await authService.authenticate()
        }
    }
}
