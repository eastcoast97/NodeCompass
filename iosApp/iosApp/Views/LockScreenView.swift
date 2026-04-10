import SwiftUI

struct LockScreenView: View {
    @ObservedObject var authService: AuthService
    @State private var logoScale: CGFloat = 0.85
    @State private var logoOpacity: CGFloat = 0
    @State private var glowOpacity: CGFloat = 0
    @State private var contentOpacity: CGFloat = 0

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.09),
                    Color(red: 0.08, green: 0.09, blue: 0.14),
                    Color(red: 0.04, green: 0.05, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo
                VStack(spacing: 24) {
                    ZStack {
                        // Ambient glow
                        Circle()
                            .fill(NC.teal.opacity(0.12))
                            .frame(width: 180, height: 180)
                            .blur(radius: 50)
                            .opacity(glowOpacity)

                        Image("NodeCompassLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 240)
                    }
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)

                    // Tagline
                    Text("Your life, understood.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.3))
                        .opacity(contentOpacity)
                }

                Spacer()

                // Unlock
                VStack(spacing: 20) {
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
                        .padding(.vertical, 17)
                        .background(
                            LinearGradient(
                                colors: [NC.teal, NC.teal.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: NC.teal.opacity(0.25), radius: 16, y: 6)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                        Text("All data stored on-device only")
                            .font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.25))
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 56)
                .opacity(contentOpacity)
            }
        }
        .task {
            withAnimation(.easeOut(duration: 0.8)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 1.2).delay(0.2)) {
                glowOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.4)) {
                contentOpacity = 1.0
            }
            await authService.authenticate()
        }
    }
}
