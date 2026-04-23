import SwiftUI

// MARK: - Floating Particle

/// A single ambient orb that drifts slowly across the lock screen.
private struct FloatingParticle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    let size: CGFloat
    let opacity: Double
    let duration: Double
    let delay: Double
    let color: Color
}

// MARK: - Particle Field

/// Ambient floating orbs that give the lock screen a living, breathing feel.
private struct ParticleFieldView: View {
    @State private var animate = false

    let particles: [FloatingParticle] = {
        let colors: [Color] = [NC.teal, Color(hex: "#6366F1"), Color(hex: "#3B82F6")]
        return (0..<14).map { _ in
            FloatingParticle(
                x: CGFloat.random(in: 0...1),
                y: CGFloat.random(in: 0...1),
                size: CGFloat.random(in: 4...18),
                opacity: Double.random(in: 0.04...0.18),
                duration: Double.random(in: 6...14),
                delay: Double.random(in: 0...4),
                color: colors.randomElement()!
            )
        }
    }()

    var body: some View {
        GeometryReader { geo in
            ForEach(particles) { p in
                Circle()
                    .fill(p.color)
                    .frame(width: p.size, height: p.size)
                    .blur(radius: p.size * 0.8)
                    .opacity(p.opacity)
                    .position(
                        x: animate ? p.x * geo.size.width + 30 : p.x * geo.size.width - 30,
                        y: animate ? p.y * geo.size.height - 20 : p.y * geo.size.height + 20
                    )
                    .animation(
                        .easeInOut(duration: p.duration)
                        .repeatForever(autoreverses: true)
                        .delay(p.delay),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

// MARK: - Pulsing Ring

/// Breathing glow ring around the app icon.
private struct PulsingRingView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Outer soft glow
            Circle()
                .stroke(NC.teal.opacity(0.15), lineWidth: 1.5)
                .frame(width: 170, height: 170)
                .scaleEffect(pulse ? 1.12 : 0.95)
                .opacity(pulse ? 0.0 : 0.6)

            // Inner ring
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [NC.teal.opacity(0.5), NC.teal.opacity(0.0), Color(hex: "#6366F1").opacity(0.3), NC.teal.opacity(0.5)],
                        center: .center
                    ),
                    lineWidth: 1.5
                )
                .frame(width: 150, height: 150)
                .scaleEffect(pulse ? 1.04 : 1.0)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Glassmorphic Button

private struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.25), value: configuration.isPressed)
    }
}

// MARK: - Lock Screen

struct LockScreenView: View {
    @ObservedObject var authService: AuthService

    // Staggered entrance states
    @State private var showIcon = false
    @State private var showRing = false
    @State private var showTitle = false
    @State private var showTagline = false
    @State private var showFooter = false
    @State private var iconFloat = false

    var body: some View {
        ZStack {
            // Deep background
            Color(red: 0.03, green: 0.03, blue: 0.07)
                .ignoresSafeArea()

            // Gradient overlay
            RadialGradient(
                colors: [
                    NC.teal.opacity(0.06),
                    Color(hex: "#6366F1").opacity(0.03),
                    .clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()

            // Floating particles
            ParticleFieldView()
                .ignoresSafeArea()

            // Main content
            VStack(spacing: 0) {
                Spacer()

                // Icon + glow ring
                ZStack {
                    // Deep ambient glow behind icon
                    Circle()
                        .fill(NC.teal.opacity(0.08))
                        .frame(width: 220, height: 220)
                        .blur(radius: 60)
                        .opacity(showRing ? 1.0 : 0.0)

                    // Pulsing ring
                    if showRing {
                        PulsingRingView()
                    }

                    // App icon
                    Image("LockIcon")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 110, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .shadow(color: NC.teal.opacity(0.35), radius: 30, y: 4)
                        .shadow(color: Color(hex: "#6366F1").opacity(0.15), radius: 20, y: 0)
                        .scaleEffect(showIcon ? 1.0 : 0.6)
                        .opacity(showIcon ? 1.0 : 0.0)
                        .offset(y: iconFloat ? -3 : 3)
                }
                .padding(.bottom, 32)

                // App name
                HStack(spacing: 2) {
                    Text("Node")
                        .font(.system(size: 32, weight: .thin, design: .default))
                    Text("Compass")
                        .font(.system(size: 32, weight: .bold, design: .default))
                }
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .white.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .opacity(showTitle ? 1.0 : 0.0)
                .offset(y: showTitle ? 0 : 12)
                .padding(.bottom, 10)

                // Tagline
                Text("Your life, understood.")
                    .font(.system(size: 15, weight: .regular, design: .default))
                    .foregroundStyle(.white.opacity(0.35))
                    .opacity(showTagline ? 1.0 : 0.0)
                    .offset(y: showTagline ? 0 : 8)

                Spacer()

                // Privacy footer + Face ID hint
                VStack(spacing: 16) {
                    // Face ID icon — tap to retry
                    Button {
                        Haptic.light()
                        Task { await authService.authenticate() }
                    } label: {
                        Image(systemName: "faceid")
                            .font(.system(size: 28, weight: .thin))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                    .buttonStyle(.plain)
                    .opacity(showFooter ? 1.0 : 0.0)

                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 10))
                        Text("All data stored on-device only")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.2))
                    .opacity(showFooter ? 1.0 : 0.0)
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 56)
            }
        }
        .task {
            // Staggered entrance sequence
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                showIcon = true
            }

            try? await Task.sleep(nanoseconds: 200_000_000)
            withAnimation(.easeOut(duration: 0.8)) {
                showRing = true
            }

            try? await Task.sleep(nanoseconds: 150_000_000)
            withAnimation(.easeOut(duration: 0.5)) {
                showTitle = true
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.easeOut(duration: 0.5)) {
                showTagline = true
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
            withAnimation(.easeOut(duration: 0.4)) {
                showFooter = true
            }

            // Start gentle icon float
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                iconFloat = true
            }

            // Auto-trigger Face ID immediately after animations
            await authService.authenticate()
        }
    }
}
